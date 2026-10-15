-- wezterm_common.lua (shared across OSes)
local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

-- opts = { font_families, show_new_tab_button }
function M.build_base(opts)
    local config = wezterm.config_builder()

    -- Basic behavior
    config.automatically_reload_config = true
    config.audible_bell = "Disabled"
    config.visual_bell = {
        fade_in_duration_ms = 0,
        fade_out_duration_ms = 0,
    }

    ------------------------------------------------------------
    -- Fonts
    ------------------------------------------------------------
    local main_font = wezterm.font_with_fallback(opts.font_families)

    config.font = main_font
    config.font_size = 11.0
    config.use_ime = true
    config.bold_brightens_ansi_colors = false

    -- Keep Bold using the same fallback set to avoid font hopping
    -- Italic is rendered upright: italic faces are not installed, and
    -- requesting them pops up a configuration error window.
    config.font_rules = {
        {
            intensity = "Bold",
            italic = false,
            font = main_font,
        },
        {
            italic = true,
            font = main_font,
        },
    }


    ------------------------------------------------------------
    -- Bell -> tab attention (no sound / no flash)
    ------------------------------------------------------------
    local function needs_attn_key(tab_id)
        return "needs_attn:" .. tostring(tab_id)
    end
    local function active_tab_key(window)
        return "active_tab:" .. tostring(window:window_id())
    end
    local function clear_active_tab_attention(window)
        local tab = window:active_tab()
        if tab then
            wezterm.GLOBAL[needs_attn_key(tab:tab_id())] = nil
        end
    end

    wezterm.on("bell", function(window, pane)
        local tab = pane:tab()
        if not tab then
            return
        end

        if window and window:is_focused() then
            local active_tab = window:active_tab()
            if active_tab and active_tab:tab_id() == tab:tab_id() then
                return
            end
        end

        wezterm.GLOBAL[needs_attn_key(tab:tab_id())] = true
    end)

    wezterm.on("update-status", function(window, _)
        local tab = window:active_tab()
        if not tab then
            return
        end

        local key = active_tab_key(window)
        local tab_id = tab:tab_id()
        local previous_tab_id = wezterm.GLOBAL[key]
        wezterm.GLOBAL[key] = tab_id

        if window:is_focused()
            and previous_tab_id
            and previous_tab_id ~= tab_id
        then
            clear_active_tab_attention(window)
        end
    end)

    -- Switch to alphanumeric input when the window becomes active.
    -- wezterm cannot switch input sources itself, so call an external command.
    -- Windows: turn the IME off with im-switch (cargo install im-switch)
    -- macOS:   switch the input source to ABC with im-switch
    -- Linux:   deactivate the input method with fcitx5-remote -c
    local triple = wezterm.target_triple
    local im_switch = wezterm.home_dir .. "/.cargo/bin/im-switch"
    local im_off_args
    if triple:find("windows") then
        im_off_args = { im_switch, "ime", "off" }
    elseif triple:find("darwin") then
        im_off_args = { im_switch, "set", "com.apple.keylayout.ABC" }
    else
        im_off_args = { "fcitx5-remote", "-c" }
    end

    wezterm.on("window-focus-changed", function(window, _)
        if window:is_focused() then
            clear_active_tab_attention(window)
            wezterm.background_child_process(im_off_args)
        end
    end)

    ------------------------------------------------------------
    -- Appearance / Tab bar / Cursor
    ------------------------------------------------------------
    config.default_cursor_style = "BlinkingBar"
    config.window_decorations = "RESIZE"

    config.show_tabs_in_tab_bar = true
    config.hide_tab_bar_if_only_one_tab = false
    config.show_new_tab_button_in_tab_bar = opts.show_new_tab_button
    config.show_close_tab_button_in_tabs = false

    config.colors = config.colors or {}
    config.colors.tab_bar = config.colors.tab_bar or {}
    config.colors.tab_bar.inactive_tab_edge = "none"

    -- Fancy tab titles using nerd fonts
    local SOLID_LEFT_ARROW = wezterm.nerdfonts.ple_left_half_circle_thick
    local SOLID_RIGHT_ARROW = wezterm.nerdfonts.ple_right_half_circle_thick
    local TRANSPARENT = "rgba(0,0,0,0)"

    local TAB = {
        inactive_bg = "#5c6d74",
        active_bg   = "#8a9dbf",
        fg          = "#FFFFFF",
    }

    wezterm.on("format-tab-title", function(tab, _, _, _, _, max_width)
        local bg
        if wezterm.GLOBAL[needs_attn_key(tab.tab_id)] then
            bg = "#a05671"
        else
            bg = tab.is_active and TAB.active_bg or TAB.inactive_bg
        end
        local fg = TAB.fg
        local title = "   " .. wezterm.truncate_right(tab.active_pane.title, max_width - 1) .. "   "

        return {
            { Background = { Color = TRANSPARENT } },
            { Foreground = { Color = bg } },
            { Text = SOLID_LEFT_ARROW },

            { Background = { Color = bg } },
            { Foreground = { Color = fg } },
            { Text = title },

            { Background = { Color = TRANSPARENT } },
            { Foreground = { Color = bg } },
            { Text = SOLID_RIGHT_ARROW },
        }
    end)

    ------------------------------------------------------------
    -- Key bindings (tmux-like)
    ------------------------------------------------------------
    local kb = require("keybinds")
    config.disable_default_key_bindings = true
    config.keys = kb.keys
    config.key_tables = kb.key_tables or {}

    ------------------------------------------------------------
    -- Mouse bindings
    -- 1) When selection is completed, copy to Clipboard
    -- 2) Right-click pastes from Clipboard
    ------------------------------------------------------------
    config.mouse_bindings = config.mouse_bindings or {}

    -- On left-button release, complete selection and copy to clipboard
    table.insert(config.mouse_bindings, 1, {
        event = { Up = { streak = 1, button = "Left" } },
        mods = "NONE",
        action = act.CompleteSelectionOrOpenLinkAtMouseCursor("Clipboard"),
    })

    -- Right-click always pastes
    table.insert(config.mouse_bindings, 1, {
        event = { Down = { streak = 1, button = "Right" } },
        mods = "NONE",
        action = act.PasteFrom("Clipboard"),
    })

    return config
end

return M
