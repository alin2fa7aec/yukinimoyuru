-- keybinds_common.lua (tmux-like, shared across OSes)
local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

-- opts = { mod, tab_prev_mods, palette_mods, copy_mods }
function M.build(opts)
    return {
        keys = {
            -- --- tab ---
            -- t is added per OS (keybinds_win.lua / keybinds_mac.lua)
            { key = "Tab",        mods = "CTRL",             action = act.ActivateTabRelative(1) },
            { key = "Tab",        mods = opts.tab_prev_mods, action = act.ActivateTabRelative(-1) },
            { key = "n",          mods = "LEADER",           action = act.ActivateTabRelative(1) },
            { key = "p",          mods = "LEADER",           action = act.ActivateTabRelative(-1) },
            { key = "w",          mods = opts.mod,           action = act.CloseCurrentTab { confirm = true } },
            { key = "L",          mods = "LEADER|SHIFT",     action = act.ActivateLastTab },

            -- List (like tmux's choose-tree)
            { key = "w",          mods = "LEADER",           action = act.ShowLauncherArgs { flags = "FUZZY|TABS" } },
            { key = "s",          mods = "LEADER",           action = act.ShowLauncherArgs { flags = "FUZZY|WORKSPACES|TABS" } },

            -- Command palette
            { key = "p",          mods = opts.palette_mods,  action = act.ActivateCommandPalette },

            -- kill window(tab) / kill pane
            { key = "&",          mods = "LEADER|SHIFT",     action = act.CloseCurrentTab { confirm = true } },
            { key = "x",          mods = "LEADER",           action = act.CloseCurrentPane { confirm = true } },

            -- --- split panes ---
            { key = "\\",         mods = opts.mod,           action = act.SplitHorizontal { domain = "CurrentPaneDomain" } },
            { key = "¥",          mods = opts.mod,           action = act.SplitHorizontal { domain = "CurrentPaneDomain" } },
            { key = "^",          mods = opts.mod,           action = act.SplitVertical { domain = "CurrentPaneDomain" } },

            -- --- tmux: pane navigation ---
            { key = "LeftArrow",  mods = "LEADER",           action = act.ActivatePaneDirection("Left") },
            { key = "DownArrow",  mods = "LEADER",           action = act.ActivatePaneDirection("Down") },
            { key = "UpArrow",    mods = "LEADER",           action = act.ActivatePaneDirection("Up") },
            { key = "RightArrow", mods = "LEADER",           action = act.ActivatePaneDirection("Right") },
            { key = "o",          mods = "LEADER",           action = act.ActivatePaneDirection("Next") },

            -- search mode
            { key = "f",          mods = "LEADER",           action = act.Search("CurrentSelectionOrEmptyString") },

            -- copy-mode / paste (tmux: [ / ])
            { key = "[",          mods = "LEADER",           action = act.ActivateCopyMode },
            { key = "]",          mods = "LEADER",           action = act.PasteFrom("Clipboard") },

            -- resize mode (tmux: enter with prefix + r, then repeat hjkl)
            {
                key = "r",
                mods = "LEADER",
                action = act.ActivateKeyTable {
                    name = "resize_pane",
                    one_shot = false,
                    until_unknown = true,
                    replace_current = true,
                },
            },

            -- help (list of wezterm bindings)
            { key = "?", mods = "LEADER|SHIFT", action = act.ShowLauncherArgs { flags = "FUZZY|KEY_ASSIGNMENTS" } },

            -- Minimal direct copy/paste (separate from the mouse requirement)
            { key = "c", mods = opts.copy_mods, action = act.CopyTo("Clipboard") },
            { key = "v", mods = opts.copy_mods, action = act.PasteFrom("Clipboard") },
        },

        key_tables = {
            resize_pane = {
                { key = "LeftArrow",  action = act.AdjustPaneSize { "Left", 3 } },
                { key = "DownArrow",  action = act.AdjustPaneSize { "Down", 2 } },
                { key = "UpArrow",    action = act.AdjustPaneSize { "Up", 2 } },
                { key = "RightArrow", action = act.AdjustPaneSize { "Right", 3 } },
                { key = "Escape",     action = act.PopKeyTable },
                { key = "Enter",      action = act.PopKeyTable },
                { key = "q",          action = act.PopKeyTable },
            },
        },
    }
end

return M
