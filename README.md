# nerd_icons.wezterm

A WezTerm plugin that provides icon and color resolution for tabs. Supports both YAML configuration files and programmatic setup via function arguments.

## Installation

Add to your `wezterm.lua`:

```lua
local wezterm = require("wezterm")
local config = wezterm.config_builder()

local nerd_icons = wezterm.plugin.require('https://github.com/fullstopslash/nerd_icons.wezterm')
nerd_icons.setup(config)

wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
    local icon, colors = nerd_icons:icon_and_colors_for_tab(tab, panes)
    return {
        { Foreground = { Color = colors.icon or "#007dfc" } },
        { Text = icon },
        { Text = " " },
        { Text = tab.active_pane.title },
    }
end)

return config
```

## Configuration Methods

The plugin supports two configuration methods:

1. **YAML Configuration File** - Persistent, file-based configuration
2. **Programmatic Setup** - Dynamic configuration via function arguments

Both methods can be used together, with YAML loaded first and setup options merged (or overriding if `override_yaml = true`).

## YAML Configuration

Create a config file at `~/.config/nerd-icons/config.yml`:

```yaml
config:
  ring-color-active: "#875fff"
  ring-color-inactive: "#ffffff"
  icon-color: "#007dfc"
  alert-color: "#ff0000"
  fallback-icon: "󰆍"
  prefer-host-icon: true
  use-title-as-hostname: false

icons:
  nvim: "󰨞"
  git: "󰊢"
  bash: "󰆍"
  docker: "󰡨"
  python: "󰌠"
  node: "󰎙"

sessions:
  main: "󰀄"
  work: "󰨞"

title_icons:
  "My Project": "󰉋"
  "Production": "󰓓"

hosts:
  myserver:
    icon: "󰌢"
    ring-color: "#00ff00"
    icon-color: "#00ff00"
  "*.example.com":
    icon: "󰅺"
    ring-color: "#ff8800"
```

## Programmatic Configuration

Configure icons directly in your `wezterm.lua` using the `setup` function:

```lua
local nerd_icons = wezterm.plugin.require('https://github.com/fullstopslash/nerd_icons.wezterm')

config = nerd_icons.setup(config, {
    -- Global configuration
    config = {
        fallback_icon = "󰆍",
        prefer_host_icon = true,
        ring_color_active = "#875fff",
        ring_color_inactive = "#ffffff",
        icon_color = "#007dfc",
        alert_color = "#ff0000"
    },
    
    -- App icons
    icons = {
        vim = "󰈙",
        git = "󰊢",
        docker = "󰡨",
        python = "󰌠",
        node = "󰎙"
    },
    
    -- Session icons
    sessions = {
        main = "󰀄",
        work = "󰨞"
    },
    
    -- Title-specific icons
    title_icons = {
        ["My Project"] = "󰉋",
        ["Production"] = "󰓓"
    },
    
    -- Host icons (simple string or table with colors)
    hosts = {
        -- Simple string format
        "myserver" = "󰌢",
        
        -- Table format with colors
        "prod-server" = {
            icon = "󰓓",
            ring_color = "#ff0000",
            icon_color = "#ff0000",
            alert_color = "#ff8800"
        },
        
        -- Pattern matching (wildcards)
        "*.example.com" = "󰅺"
    },
    
    -- App-specific colors
    app_colors = {
        vim = {
            ring_color = "#00ff00",
            icon_color = "#ffffff",
            alert_color = "#ff0000"
        },
        git = {
            ring_color = "#f14e32",
            icon_color = "#f14e32"
        }
    },
    
    -- Override YAML if true, merge if false (default)
    override_yaml = false
})
```

## Use Cases

### Use Case 1: YAML-Only Configuration

Best for users who prefer file-based configuration and want to keep their `wezterm.lua` minimal:

```lua
local nerd_icons = wezterm.plugin.require('https://github.com/fullstopslash/nerd_icons.wezterm')
nerd_icons.setup(config)
```

All configuration is done in `~/.config/nerd-icons/config.yml`.

### Use Case 2: Programmatic-Only Configuration

Best for users who want everything in their `wezterm.lua` without external files:

```lua
local nerd_icons = wezterm.plugin.require('https://github.com/fullstopslash/nerd_icons.wezterm')

config = nerd_icons.setup(config, {
    icons = {
        vim = "󰈙",
        git = "󰊢"
    },
    config = {
        fallback_icon = "󰆍"
    },
    override_yaml = true  -- Ignore YAML file if it exists
})
```

### Use Case 3: Hybrid Configuration

Best for users who want base configuration in YAML with dynamic overrides:

```lua
local nerd_icons = wezterm.plugin.require('https://github.com/fullstopslash/nerd_icons.wezterm')

-- YAML provides base config, setup options add/override specific items
config = nerd_icons.setup(config, {
    icons = {
        -- Add new icons or override YAML icons
        my_custom_app = "󰀄"
    },
    hosts = {
        -- Add host-specific icons
        "dev-server" = "󰌢"
    }
    -- override_yaml defaults to false, so YAML is merged
})
```

### Use Case 4: Environment-Specific Configuration

Dynamically configure based on environment variables or system detection:

```lua
local nerd_icons = wezterm.plugin.require('https://github.com/fullstopslash/nerd_icons.wezterm')

local icon_config = {
    icons = {
        vim = "󰈙",
        git = "󰊢"
    }
}

-- Add environment-specific hosts
if os.getenv("PROD_MODE") then
    icon_config.hosts = {
        ["prod-*"] = { icon = "󰓓", ring_color = "#ff0000" }
    }
else
    icon_config.hosts = {
        ["dev-*"] = { icon = "󰌢", ring_color = "#00ff00" }
    }
end

config = nerd_icons.setup(config, icon_config)
```

## Configuration Options

### Global Config (`options.config`)

- `fallback_icon` - Icon to use when no match is found
- `prefer_host_icon` - Prefer host icons over app icons (default: `true`)
- `use_title_as_hostname` - Extract hostname from tab title (default: `false`)
- `ring_color_active` / `index_color_active` - Color for active tab index ring
- `ring_color_inactive` / `index_color_inactive` - Color for inactive tab index ring
- `ring_color` / `index_color` - Color for both active and inactive rings
- `icon_color` - Default icon color
- `alert_color` - Color for tabs with alerts

### Icons (`options.icons`)

Map application names (lowercase) to icon glyphs. The plugin matches against process names and tab titles.

### Sessions (`options.sessions`)

Map session/workspace names to icon glyphs.

### Title Icons (`options.title_icons`)

Map exact tab titles to icon glyphs. Useful for specific project names or window titles.

### Hosts (`options.hosts`)

Map hostnames to icons. Supports:
- **Simple format**: `"hostname" = "icon"`
- **Table format**: `"hostname" = { icon = "...", ring_color = "...", icon_color = "...", alert_color = "..." }`
- **Pattern matching**: Use wildcards like `"*.example.com"` for pattern-based matching

### App Colors (`options.app_colors`)

Set colors for specific applications:
```lua
app_colors = {
    app_name = {
        ring_color = "#color",
        icon_color = "#color",
        alert_color = "#color"
    }
}
```

## API

### `nerd_icons:icon_and_colors_for_tab(tab, panes)`

Returns the icon and color hints for a tab. Used in `format-tab-title` event handler.

**Returns:**
- `icon` (string) - The icon glyph for the tab
- `colors` (table) - Color hints with keys: `ring`, `ringActive`, `ringInactive`, `icon`, `alert`

### `nerd_icons.icon_for_title(title)`

Get icon for a specific title string.

**Returns:** `icon` (string)

### `nerd_icons.get_global_icon_color()`

Get the global icon color from configuration.

**Returns:** `color` (string) or `nil`

### `nerd_icons.get_fallback_icon()`

Get the fallback icon from configuration.

**Returns:** `icon` (string)

## License

MIT License
