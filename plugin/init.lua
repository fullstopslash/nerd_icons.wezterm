local wezterm = require("wezterm")

local M = {}
local default_app_glyph = wezterm.nerdfonts and wezterm.nerdfonts.dev_terminal or "?"

-- Configuration state
local ICON_MAP_CACHE = nil
local TITLE_PATTERN_CACHE = nil
local TITLE_ICONS_MAP = nil
local SESSIONS_MAP = nil
local FALLBACK_ICON = nil
local PREFER_HOST_ICON = true
local USE_TITLE_AS_HOSTNAME = false
local HOST_ICON_EXACT = nil
local HOST_ICON_PATTERNS = nil
local HOST_COLOR_EXACT = nil
local HOST_COLOR_PATTERNS = nil
local GLOBAL_RING_ACTIVE = nil
local GLOBAL_RING_INACTIVE = nil
local GLOBAL_ICON_COLOR = nil
local GLOBAL_ALERT_COLOR = nil
local APP_COLOR_MAP = nil

-- Pattern conversion cache
local PATTERN_CACHE = {}

-- Utility functions
local function expanduser(path)
	if not path then return nil end
	if path:sub(1, 1) == "~" then
		return (os.getenv("HOME") or "") .. path:sub(2)
	end
	return path
end

local function file_exists(path)
	local p = expanduser(path)
	local f = p and io.open(p, "r")
	if f then f:close(); return true end
	return false
end

local function read_lines(path)
	local p = expanduser(path)
	local f = p and io.open(p, "r")
	if not f then return nil end
	local lines = {}
	for line in f:lines() do table.insert(lines, line) end
	f:close()
	return lines
end

local function sanitize_yaml_value(v)
	if not v then return v end
	local part = v
	local idx = part:find(" #", 1, true)
	if idx then part = part:sub(1, idx - 1) end
	part = part:gsub("^%s+", ""):gsub("%s+$", "")
	if #part >= 2 then
		local q1 = part:sub(1, 1)
		local q2 = part:sub(-1)
		if (q1 == '"' or q1 == "'") and q1 == q2 then
			part = part:sub(2, -2)
		end
	end
	return part
end

local function count_indent(s)
	local prefix = s:match("^(%s*)") or ""
	return #prefix
end

local function resolve_icon_config_path()
	local env = os.getenv("KITTY_ICON_CONFIG") or os.getenv("WAYBAR_ICON_CONFIG")
	if env and file_exists(env) then return expanduser(env) end
	return (os.getenv("HOME") or "") .. "/.config/nerd-icons/config.yml"
end

local function parse_bool(val)
	if not val then return false end
	local lc = val:lower()
	return (lc == "true" or lc == "yes" or lc == "1" or lc == "on")
end

-- Convert shell wildcard pattern to Lua pattern (with caching)
local function pattern_to_lua(pat)
	if not pat then return nil end
	if PATTERN_CACHE[pat] then
		return PATTERN_CACHE[pat]
	end
	local converted = pat:gsub("%%", "%%%%"):gsub("%.", "%%."):gsub("%*", ".*"):gsub("%?", ".")
	PATTERN_CACHE[pat] = converted
	return converted
end

-- Extract process name from path
local function extract_proc_name(path)
	if not path then return nil end
	return path:match("([^/]+)$") or path
end

-- Tokenize title into candidates
local function tokenize_title(title)
	if not title or title == "" then return {} end
	local candidates = { title }
	for tok in title:gmatch("[A-Za-z0-9._+-]+") do
		if tok and tok ~= "" then
			table.insert(candidates, tok)
		end
	end
	return candidates
end

-- Get pane info from tab (cached)
local function get_tab_pane_info(tab)
	if not tab or not tab.panes then return nil end
	local ok, tab_panes = pcall(function() return tab.panes end)
	if not ok or not tab_panes or type(tab_panes) ~= "table" or #tab_panes == 0 then
		return nil
	end
	local pane_info = nil
	for i, pi in ipairs(tab_panes) do
		if pi.is_active then
			pane_info = pi
			break
		end
	end
	return pane_info or tab_panes[1]
end

-- Parse config block
local function parse_config(lines)
	local in_config = false
	local config_indent = nil
	for _, raw in ipairs(lines) do
		local stripped = raw:gsub("^%s+", ""):gsub("%s+$", "")
		if not in_config then
			if stripped:match("^config:%s*") then
				in_config = true
				config_indent = nil
			end
		else
			if stripped ~= "" and not raw:match("^%s*#") then
				local cur_indent = count_indent(raw)
				if not config_indent then config_indent = cur_indent end
				if cur_indent < config_indent then break end
				if raw:find(":") then
					local k, v = raw:match("^%s*([^:]+):%s*(.*)$")
					if k then
						k = sanitize_yaml_value(k):lower()
						local val = sanitize_yaml_value(v)
						if k == "fallback-icon" and val and val ~= "" then
							FALLBACK_ICON = val
						elseif k == "prefer-host-icon" then
							PREFER_HOST_ICON = parse_bool(val)
						elseif k == "use-title-as-hostname" then
							USE_TITLE_AS_HOSTNAME = parse_bool(val)
						elseif (k == "ring-color-active" or k == "index-color-active") and val and val ~= "" then
							GLOBAL_RING_ACTIVE = val
						elseif (k == "ring-color-inactive" or k == "index-color-inactive") and val and val ~= "" then
							GLOBAL_RING_INACTIVE = val
						elseif (k == "ring-color" or k == "index-color") and val and val ~= "" then
							GLOBAL_RING_ACTIVE = GLOBAL_RING_ACTIVE or val
							GLOBAL_RING_INACTIVE = GLOBAL_RING_INACTIVE or val
						elseif k == "icon-color" and val and val ~= "" then
							GLOBAL_ICON_COLOR = val
						elseif k == "alert-color" and val and val ~= "" then
							GLOBAL_ALERT_COLOR = val
						end
					end
				end
			end
		end
	end
end

-- Parse app/host/session blocks
local function parse_app_block(lines, label)
	local map = {}
	local title_patterns_map = {}
	local in_block = false
	local indent_level = nil
	local i = 1
	while i <= #lines do
		local raw = lines[i]
		local stripped = raw:gsub("^%s+", ""):gsub("%s+$", "")
		if not in_block then
			if stripped:match("^" .. label .. "%s*") then
				in_block = true
				indent_level = nil
			end
			i = i + 1
		else
			if not stripped or raw:match("^%s*#") then
				i = i + 1
			else
				local cur_indent = count_indent(raw)
				if not indent_level then indent_level = cur_indent end
				if cur_indent < indent_level then break end
				if raw:find(":") then
					local key_part, rest = raw:match("^%s*([^:]+):%s*(.*)$")
					if key_part then
						local app_key = sanitize_yaml_value(key_part):lower()
						if app_key and app_key ~= "" then
							local val = sanitize_yaml_value(rest)
							if val and val ~= "" and not val:match("^[|>{%[]") then
								map[app_key] = val
								i = i + 1
							else
								local base = cur_indent
								local nested_icon = nil
								local colors = nil
								local title_patterns = {}
								local j = i + 1
								while j <= #lines do
									local lj = lines[j]
									local strippedj = lj:gsub("^%s+", ""):gsub("%s+$", "")
									if strippedj ~= "" and not lj:match("^%s*#") then
										local indj = count_indent(lj)
										if indj <= base then break end
										if lj:find(":") then
											local nk, nv = lj:match("^%s*([^:]+):%s*(.*)$")
											if nk then
												nk = sanitize_yaml_value(nk):lower()
												nv = sanitize_yaml_value(nv)
												if nk == "icon" and nv and nv ~= "" then
													nested_icon = nv
												elseif nk == "title" then
													local title_base = indj
													local k = j + 1
													while k <= #lines do
														local lk = lines[k]
														local strippedk = lk:gsub("^%s+", ""):gsub("%s+$", "")
														if strippedk ~= "" and not lk:match("^%s*#") then
															local indk = count_indent(lk)
															if indk <= title_base then break end
															if lk:find(":") then
																local tkp, tvp = lk:match("^%s*([^:]+):%s*(.*)$")
																if tkp then
																	local pattern = sanitize_yaml_value(tkp)
																	local tval = sanitize_yaml_value(tvp)
																	if pattern and tval then
																		table.insert(title_patterns, {pattern, tval})
																	end
																end
															end
														end
														k = k + 1
													end
													j = k - 1
												elseif nk == "ring-color" or nk == "index-color" or nk == "icon-color" or nk == "alert-color" then
													colors = colors or {}
													if nk == "index-color" then
														colors["ring-color"] = nv
													else
														colors[nk] = nv
													end
												end
											end
										end
									end
									j = j + 1
								end
								if nested_icon then map[app_key] = nested_icon end
								if colors then
									APP_COLOR_MAP = APP_COLOR_MAP or {}
									APP_COLOR_MAP[app_key] = colors
								end
								if #title_patterns > 0 then
									title_patterns_map[app_key] = title_patterns
								end
								i = j
							end
						else
							i = i + 1
						end
					else
						i = i + 1
					end
				else
					i = i + 1
				end
			end
		end
	end
	return map, title_patterns_map
end

-- Load configuration
local function ensure_loaded()
	if ICON_MAP_CACHE ~= nil then return end
	ICON_MAP_CACHE = {}
	TITLE_PATTERN_CACHE = {}
	TITLE_ICONS_MAP = {}
	SESSIONS_MAP = {}
	HOST_ICON_EXACT = {}
	HOST_ICON_PATTERNS = {}
	HOST_COLOR_EXACT = {}
	HOST_COLOR_PATTERNS = {}
	APP_COLOR_MAP = {}
	
	local cfg_path = resolve_icon_config_path()
	local lines = read_lines(cfg_path)
	if not lines or #lines == 0 then return end
	
	parse_config(lines)
	local icons, icon_title_patterns = parse_app_block(lines, "icons:")
	local sessions, _ = parse_app_block(lines, "sessions:")
	local title_icons, _ = parse_app_block(lines, "title_icons:")
	
	for k, v in pairs(icons) do
		if k and k ~= "" and v and v ~= "" then
			ICON_MAP_CACHE[k] = v
		end
	end
	for k, v in pairs(sessions) do
		if k and k ~= "" and v and v ~= "" and ICON_MAP_CACHE[k] == nil then
			ICON_MAP_CACHE[k] = v
		end
	end
	
	SESSIONS_MAP = sessions
	for k, v in pairs(title_icons) do
		if k and k ~= "" and v and v ~= "" then
			TITLE_ICONS_MAP[k] = v
		end
	end
	
	for app_key, patterns in pairs(icon_title_patterns) do
		TITLE_PATTERN_CACHE[app_key] = patterns
	end
	
	-- Parse hosts block
	local in_hosts = false
	local indent_level = nil
	local i = 1
	while i <= #lines do
		local raw = lines[i]
		local stripped = raw:gsub("^%s+", ""):gsub("%s+$", "")
		if not in_hosts then
			if stripped:match("^hosts:%s*") then
				in_hosts = true
				indent_level = nil
			end
			i = i + 1
		else
			if stripped ~= "" and not raw:match("^%s*#") then
				local cur_indent = count_indent(raw)
				if not indent_level then indent_level = cur_indent end
				if cur_indent < indent_level then break end
				if raw:find(":") then
					local key_part, rest = raw:match("^%s*([^:]+):%s*(.*)$")
					if key_part then
						local host_key = sanitize_yaml_value(key_part)
						local host_key_lc = (host_key or ""):lower()
						local val = sanitize_yaml_value(rest)
						if val ~= nil and val ~= "" and not val:match("^[|>{%[]") then
							if host_key_lc:find("[%*%?%[]") then
								table.insert(HOST_ICON_PATTERNS, { host_key_lc, val })
							else
								HOST_ICON_EXACT[host_key_lc] = val
							end
							i = i + 1
						else
							local base = cur_indent
							local j = i + 1
							local icon_val = nil
							local colors = {}
							while j <= #lines do
								local lj = lines[j]
								local strippedj = lj:gsub("^%s+", ""):gsub("%s+$", "")
								if strippedj ~= "" and not lj:match("^%s*#") then
									local indj = count_indent(lj)
									if indj <= base then break end
									if lj:find(":") then
										local nk, nv = lj:match("^%s*([^:]+):%s*(.*)$")
										nk = nk and sanitize_yaml_value(nk):lower() or nil
										nv = sanitize_yaml_value(nv)
										if nk == "icon" then
											icon_val = nv
										elseif nk == "ring-color" or nk == "index-color" or nk == "icon-color" or nk == "alert-color" then
											if nk == "index-color" then
												colors["ring-color"] = nv
											else
												colors[nk] = nv
											end
										end
									end
								end
								j = j + 1
							end
							if icon_val then
								if host_key_lc:find("[%*%?%[]") then
									table.insert(HOST_ICON_PATTERNS, { host_key_lc, icon_val })
									if next(colors) then
										table.insert(HOST_COLOR_PATTERNS, { host_key_lc, colors })
									end
								else
									HOST_ICON_EXACT[host_key_lc] = icon_val
									if next(colors) then
										HOST_COLOR_EXACT[host_key_lc] = colors
									end
								end
							end
							i = j
						end
					else
						i = i + 1
					end
				else
					i = i + 1
				end
			else
				i = i + 1
			end
		end
	end
end

-- Extract hostname from title patterns
local function extract_host_from_title(title)
	if not title or title == "" then return nil end
	local host = title:match("@([%w%.%-]+)")
	if host then return host end
	host = title:match("[Ss][Ss][Hh][Hh]?%s*:?%s*([%w%.%-]+)")
	if host then return host end
	if title:match("^[%w%.%-]+$") and not title:match("^%d+") and title ~= "local" then
		return title
	end
	return nil
end

-- Parse domain name to extract host
local function parse_domain_host(domain)
	if not domain then return nil end
	local domain_lc = domain:lower()
	if domain_lc:find("ssh") or domain_lc:find("mosh") then
		local host = domain:gsub("^[Ss][Ss][Hh][Hh]?:?", ""):gsub("^[Mm][Oo][Ss][Hh]:?", ""):gsub("^%w+@", ""):gsub(":%d+$", "")
		if host ~= "" and host ~= "local" then
			return host
		end
	elseif domain:match("^[%w%.%-]+$") and domain ~= "local" and not domain:match("^%d+") then
		return domain
	end
	return nil
end

-- Check if process is SSH-related
local function is_ssh_process(proc_name)
	if not proc_name then return false end
	local base = extract_proc_name(proc_name)
	return (base == "ssh" or base == "mosh" or base == "mosh-client" or base == "slogin")
end

-- Detect SSH host from pane (active tabs)
local function detect_ssh_host_from_pane(pane)
	if not pane then return nil end
	
	if USE_TITLE_AS_HOSTNAME then
		local ok, title = pcall(function() return pane.title end)
		if ok and title and title ~= "" then
			local host = extract_host_from_title(title)
			if host then return host end
			-- Check if SSH process and title is hostname
			local ok_info, info = pcall(function() return pane:get_foreground_process_info() end)
			if ok_info and info and info.executable and is_ssh_process(info.executable) then
				if title:match("^[%w%.%-]+$") and not title:match("^%d+") and title ~= "local" then
					return title
				end
			end
		end
	end
	
	-- Fallback: inspect process argv
	local ok, info = pcall(function() return pane:get_foreground_process_info() end)
	if ok and info and info.executable then
		if not is_ssh_process(info.executable) then return nil end
		local args = info.argv or {}
		local function first_non_option(argv)
			local i = 1
			local consume_set = {
				["-b"]=true,["-c"]=true,["-D"]=true,["-E"]=true,["-F"]=true,["-I"]=true,["-J"]=true,
				["-L"]=true,["-l"]=true,["-m"]=true,["-O"]=true,["-o"]=true,["-p"]=true,["-Q"]=true,
				["-R"]=true,["-S"]=true,["-W"]=true,["-w"]=true,["-i"]=true,["-B"]=true
			}
			while i <= #argv do
				local tok = tostring(argv[i])
				if tok == "--" then return nil end
				if tok:sub(1,1) == "-" then
					if consume_set[tok] and (i + 1) <= #argv then
						i = i + 2
					else
						i = i + 1
					end
				else
					return tok
				end
			end
			return nil
		end
		local host = first_non_option(args)
		if host then
			host = host:gsub("^%w+@", ""):gsub("^%[", ""):gsub("%]$", ""):gsub(":%d+$", "")
			return host
		end
	end
	return nil
end

-- Match host icon from configuration
local function match_host_icon(host)
	if not host or host == "" then return nil, nil end
	local key = host:lower()
	
	if HOST_ICON_EXACT and HOST_ICON_EXACT[key] then
		return HOST_ICON_EXACT[key], HOST_COLOR_EXACT and HOST_COLOR_EXACT[key] or nil
	end
	
	if HOST_ICON_PATTERNS then
		for _, pair in ipairs(HOST_ICON_PATTERNS) do
			local pat, icon = pair[1], pair[2]
			local lua_pat = pattern_to_lua(pat)
			if lua_pat and key:match("^" .. lua_pat .. "$") then
				local colors = nil
				if HOST_COLOR_PATTERNS then
					for _, cp in ipairs(HOST_COLOR_PATTERNS) do
						local cp_pat = pattern_to_lua(cp[1])
						if cp_pat and key:match("^" .. cp_pat .. "$") then
							colors = cp[2]
							break
						end
					end
				end
				return icon, colors
			end
		end
	end
	
	return nil, nil
end

-- Match title against compiled patterns
local function match_title_patterns(title)
	if not title or title == "" then return nil end
	if TITLE_PATTERN_CACHE then
		for app_key, patterns in pairs(TITLE_PATTERN_CACHE) do
			for _, pattern_pair in ipairs(patterns) do
				local pattern, icon = pattern_pair[1], pattern_pair[2]
				local lua_pat = pattern_to_lua(pattern)
				if lua_pat and title:match(lua_pat) then
					return icon
				end
			end
		end
	end
	return nil
end

-- Get icon for title
function M.icon_for_title(title)
	ensure_loaded()
	local fallback = FALLBACK_ICON or default_app_glyph
	if not title or title == "" then return fallback end
	
	local title_lc = title:lower()
	
	-- Check title-specific icons
	if TITLE_ICONS_MAP and next(TITLE_ICONS_MAP) then
		if TITLE_ICONS_MAP[title_lc] then
			return TITLE_ICONS_MAP[title_lc]
		end
		for k, v in pairs(TITLE_ICONS_MAP) do
			if title_lc:find(k, 1, true) then
				return v
			end
		end
	end
	
	-- Check title patterns
	local pattern_match = match_title_patterns(title)
	if pattern_match then return pattern_match end
	
	-- Check regular icon cache
	if ICON_MAP_CACHE and next(ICON_MAP_CACHE) then
		local candidates = tokenize_title(title)
		for _, cand in ipairs(candidates) do
			local v = ICON_MAP_CACHE[cand:lower()]
			if v and v ~= "" then return v end
		end
		for k, v in pairs(ICON_MAP_CACHE) do
			if title_lc:find(k, 1, true) then
				return v
			end
		end
	end
	
	return fallback
end

-- Get fallback icon
function M.get_fallback_icon()
	ensure_loaded()
	return FALLBACK_ICON or default_app_glyph
end

-- Get global icon color from config (like tmux script's get_global_icon_color)
function M.get_global_icon_color()
	ensure_loaded()
	return GLOBAL_ICON_COLOR
end

-- Main function: get icon and colors for tab
function M.icon_and_colors_for_tab(self_or_tab, tab_or_panes, panes_arg, tabs_arg)
	local tab = tab_or_panes
	
	if not tab then
		ensure_loaded()
		return FALLBACK_ICON or default_app_glyph, {}
	end
	
	ensure_loaded()
	local fallback = FALLBACK_ICON or default_app_glyph
	local icon = fallback
	local colors = {}
	
	-- Debug: log entry for active tabs
	if tab.is_active then
		wezterm.log_info("Plugin.icon_and_colors_for_tab: Active tab " .. tostring(tab.tab_index) .. ", has active_pane: " .. tostring(tab.active_pane ~= nil))
	end
	
	-- Get title from tab-specific sources
	-- For active tabs, prioritize tab.active_pane FIRST for most accurate results
	local title = nil
	local pane_info = nil
	
	-- For active tabs, try active_pane FIRST before falling back to pane_info
	-- This ensures we get the most up-to-date information from the active pane
	if tab.is_active and tab.active_pane then
		local ap = tab.active_pane
		local ok, t1 = pcall(function() return ap.title end)
		if ok and t1 and t1 ~= "" then
			title = t1
		else
			local proc_ok, proc_info = pcall(function() return ap:get_foreground_process_info() end)
			if proc_ok and proc_info then
				local proc_name = proc_info.name or (proc_info.executable and extract_proc_name(proc_info.executable)) or nil
				if proc_name and proc_name ~= "" then
					title = proc_name
				end
			end
		end
	end
	
	-- Fallback to tab_title or pane_info if we don't have a title yet
	if (not title or title == "") then
		if tab.tab_title and tab.tab_title ~= "" then
			title = tab.tab_title
		else
			pane_info = get_tab_pane_info(tab)
			if pane_info then
				if pane_info.title and pane_info.title ~= "" then
					title = pane_info.title
				elseif pane_info.foreground_process_name then
					local proc_name = extract_proc_name(pane_info.foreground_process_name)
					if proc_name and proc_name ~= "" then
						title = proc_name
					end
				end
			end
		end
	end
	
	-- SSH host detection: prioritize active pane for active tabs, otherwise use pane_info
	local host = nil
	if tab.is_active then
		local ok, ap = pcall(function() return tab.active_pane end)
		if ok and ap then
			local ok2, detected_host = pcall(detect_ssh_host_from_pane, ap)
			if ok2 and detected_host and detected_host ~= "" then
				host = detected_host
			end
		end
	end
	
	-- For inactive tabs or if active pane check failed, use pane_info
	if not host and pane_info then
		if USE_TITLE_AS_HOSTNAME and pane_info.title then
			host = extract_host_from_title(pane_info.title)
			if not host and is_ssh_process(pane_info.foreground_process_name) then
				local likely_ssh = not pane_info.domain_name or
					pane_info.domain_name:lower():find("ssh") or
					pane_info.domain_name:lower():find("mosh")
				if likely_ssh and pane_info.title:match("^[%w%.%-]+$") and pane_info.title ~= "local" then
					host = pane_info.title
				end
			end
		end
		
		if not host and pane_info.domain_name then
			host = parse_domain_host(pane_info.domain_name)
		end
		
		if not host and is_ssh_process(pane_info.foreground_process_name) and pane_info.title and pane_info.title:match("@") then
			host = pane_info.title:match("@([%w%.%-]+)")
		end
	end
	
	-- Match host icon if detected
	if PREFER_HOST_ICON and host and host ~= "" then
		local icn, host_colors = match_host_icon(host)
		if icn and icn ~= "" then
			icon = icn
			if host_colors then
				colors.ring = host_colors["ring-color"] or colors.ring
				colors.icon = host_colors["icon-color"] or colors.icon
				colors.alert = host_colors["alert-color"] or colors.alert
			end
			colors.ringActive = colors.ringActive or GLOBAL_RING_ACTIVE
			colors.ringInactive = colors.ringInactive or GLOBAL_RING_INACTIVE
			colors.icon = colors.icon or GLOBAL_ICON_COLOR
			colors.alert = colors.alert or GLOBAL_ALERT_COLOR
			return icon, colors
		end
	end
	
	-- Resolve icon from title
	if title and title ~= "" then
		local resolved = M.icon_for_title(title)
		if resolved and resolved ~= "" then
			icon = resolved
		end
	end
	
	-- Look up app-specific colors (reuse tokenization)
	if title and title ~= "" and APP_COLOR_MAP and next(APP_COLOR_MAP) then
		local candidates = tokenize_title(title)
		for _, cand in ipairs(candidates) do
			local col = APP_COLOR_MAP[cand:lower()]
			if col then
				colors.ring = col["ring-color"] or colors.ring
				colors.icon = col["icon-color"] or colors.icon
				colors.alert = col["alert-color"] or colors.alert
				break
			end
		end
	end
	
	-- Apply global defaults
	colors.ringActive = colors.ringActive or GLOBAL_RING_ACTIVE
	colors.ringInactive = colors.ringInactive or GLOBAL_RING_INACTIVE
	colors.icon = colors.icon or GLOBAL_ICON_COLOR
	colors.alert = colors.alert or GLOBAL_ALERT_COLOR
	
	return icon, colors
end

function M.setup(config, options)
	-- Setup function for compatibility with plugin loading pattern
	-- Configuration is loaded lazily on first use
	return config
end

return M
