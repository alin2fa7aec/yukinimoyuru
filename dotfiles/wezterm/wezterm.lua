-- wezterm.lua (Linux)

local common = require("wezterm_common")

local config = common.build_base({
    font_families = {
        { family = "Moralerspace Krypton HW", weight = "Regular" },
        { family = "JetBrains Mono" },        -- fallback
        { family = "Noto Sans Mono CJK JP" }, -- for CJK
    },
    show_new_tab_button = false,
})

local THEME = "nordfox"

-- Keep bash as the login shell, but start nushell in wezterm
config.default_prog = { "nu" }

-- On Wayland, window decorations are drawn client side, so the shared "RESIZE" setting (no title bar) cannot be dragged to move.
-- Add a title bar so the window can be moved and resized.
config.window_decorations = "TITLE | RESIZE"

-- Make the background translucent. niri blurs it with a window rule (dotfiles/niri/config.kdl).
-- On Plasma (KWin) and others, wezterm requests the blur
config.window_background_opacity = 0.92
config.wayland_window_background_blur = true

-- tmux-style leader: Ctrl+q
config.leader = { key = "q", mods = "CTRL", timeout_milliseconds = 2000 }

-- If IME input has problems on Wayland, switch to going through XWayland
-- config.enable_wayland = false

------------------------------------------------------------
-- Final defaults and return
------------------------------------------------------------
config.color_scheme = config.color_scheme or THEME

return config
