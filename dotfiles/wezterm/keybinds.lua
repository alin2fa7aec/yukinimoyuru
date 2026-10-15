-- keybinds.lua (tmux-like, Linux)
local wezterm = require("wezterm")
local act = wezterm.action
local common = require("keybinds_common")

local kb = common.build({
    mod           = "CTRL",
    tab_prev_mods = "CTRL|SHIFT",
    palette_mods  = "CTRL|SHIFT",
    copy_mods     = "ALT",
})

-- new tab (on Windows it is bound in wezterm_win.lua)
table.insert(kb.keys, { key = "t", mods = "CTRL", action = act.SpawnTab("CurrentPaneDomain") })

-- Claude Code submit: ctrl+enter -> alt+enter (meta+enter)
table.insert(kb.keys, { key = "Enter", mods = "CTRL", action = act.SendKey { key = "Enter", mods = "ALT" } })

return kb
