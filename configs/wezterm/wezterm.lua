local wezterm = require("wezterm")
local config = wezterm.config_builder()

local mux = wezterm.mux

local is_macos = wezterm.target_triple:find("apple") ~= nil
local is_linux = wezterm.target_triple:find("linux") ~= nil
local is_wsl = os.getenv("WSL_DISTRO_NAME") ~= nil or os.getenv("WSL_INTEROP") ~= nil

config.font = wezterm.font_with_fallback({
  "JetBrainsMono Nerd Font",
  "Noto Sans CJK SC",
})
config.font_size = 14.0
config.color_scheme = "Tokyo Night"
config.window_background_opacity = 0.9

config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = true

config.window_padding = {
  left = 8,
  right = 8,
  top = 8,
  bottom = 8,
}

config.scrollback_lines = 10000
-- config.initial_cols = 120
-- config.initial_rows = 40

config.window_close_confirmation = "AlwaysPrompt"
config.keys = {
  {
    key = 'w',
    mods = 'CMD',
    action = wezterm.action.CloseCurrentTab { confirm = true },
  },
}

if is_macos then
  config.macos_window_background_blur = 20
  config.native_macos_fullscreen_mode = true
  wezterm.on("gui-startup", function(cmd)
    local tab, pane, window = mux.spawn_window(cmd or {})
    window:gui_window():toggle_fullscreen()
  end)
elseif is_linux and not is_wsl then
  wezterm.on("gui-startup", function(cmd)
    local tab, pane, window = mux.spawn_window(cmd or {})
    window:gui_window():maximize()
  end)
end

return config
