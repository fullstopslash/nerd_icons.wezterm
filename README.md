# nerd_icons.wezterm

A WezTerm plugin that provides YAML-driven icon and color resolution for tabs.

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
        { Text = icon },
        { Text = " " },
        { Text = tab.active_pane.title },
    }
end)

return config
```

## Configuration

Create a config file at `~/.config/nerd-icons/config.yml`:

```yaml
config:
  ring-color-active: "#875fff"
  ring-color-inactive: "#ffffff"
  icon-color: "#007dfc"
  alert-color: "#ff0000"
  fallback-icon: "󰆍"

icons:
  nvim: "󰨞"
  git: "󰊢"
  bash: "󰆍"

hosts:
  myserver:
    icon: "󰌢"
    ring-color: "#00ff00"
```

## License

MIT License

