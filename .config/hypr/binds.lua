-- Keybindings
local mainMod = "SUPER"
local terminal = "kitty"
local fileManager = "thunar"
local menu = "~/.config/wofi/drun.sh"
local browser = "zen-browser"

-- Basic binds
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + CTRL + B", hl.dsp.exec_cmd("zen-browser --private-window"))

hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + J", hl.dsp.exec_cmd("qjackctl"))
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd("zeditor"))

-- SUPER+K for Krita (fixed conflict - was also Kdenlive)
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("krita"))

-- SUPER+CTRL+SHIFT+B for Blender
hl.bind(mainMod .. " + CTRL + SHIFT + B", hl.dsp.exec_cmd("blender"))
hl.bind(mainMod .. " + Y", hl.dsp.exec_cmd(terminal .. " yazi"))

-- SUPER+SHIFT binds
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd("lutris"))
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd("vesktop"))
hl.bind(mainMod .. " + SHIFT + D", hl.dsp.exec_cmd("discord-wayland"))
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd("~/.local/bin/translatepop"))

-- SUPER+SHIFT+E opens hyprland.lua (updated from hyprland.conf)
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exec_cmd("code /home/elia1995/.config/hypr"))

hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("hyprctl reload"))
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd("sh -c 'pkill -x quickshell; exec quickshell --path /home/elia1995/.config/quickshell --daemonize'"))
hl.bind(mainMod .. " + SHIFT + Y", hl.dsp.exec_cmd("~/.config/hypr/themes/selector.sh cycle"))
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exit())
hl.bind(mainMod .. " + CTRL + S", hl.dsp.exec_cmd("steam"))

-- HyprGlass GUI bind
hl.bind(mainMod .. " + G", hl.dsp.exec_cmd("hyprglass-gui"))

-- Additional binds
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("Telegram"))
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd("obs"))
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("code"))
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd("spotify"))

hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy --type image/png'))
hl.bind("Print", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh region"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh screen"))
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("~/.config/hypr/scripts/powermenu.sh"))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("loginctl lock-session"))

-- ALT+TAB: cycle through windows (SHIFT reverses)
hl.bind("ALT + TAB", hl.dsp.window.cycle_next({ next = true }))
hl.bind("ALT + SHIFT + TAB", hl.dsp.window.cycle_next({ next = false }))

-- Focus floating windows (Sway focus mode_toggle equivalent)
hl.bind(mainMod .. " + SPACE", hl.dsp.window.cycle_next({ floating = true }))
hl.bind(mainMod .. " + SHIFT + SPACE", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + A", hl.dsp.layout("focusmaster"))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
-- hl.bind(mainMod .. " + CTRL + W", hl.dsp.group.changegroupactive({ type = "f" })) -- No Lua equivalent
hl.bind(mainMod .. " + CTRL + L", hl.dsp.layout("togglesplit"))

-- Rice controls: wallpaper picker / next wallpaper / accent picker / lock
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("~/.config/hypr/scripts/wallpaper.sh pick"))
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("~/.config/hypr/scripts/wallpaper.sh next"))
hl.bind(mainMod .. " + ALT + W", hl.dsp.exec_cmd("~/.config/hypr/scripts/accent.sh pick"))
hl.bind(mainMod .. " + ALT + N", hl.dsp.exec_cmd("~/.config/hypr/scripts/accent.sh next"))
hl.bind(mainMod .. " + ALT + L", hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(mainMod .. " + ALT + G", hl.dsp.exec_cmd("~/.local/bin/hyprglass-gui"))  -- HyprGlass settings
hl.bind(mainMod .. " + ALT + S", hl.dsp.exec_cmd("~/.local/bin/hypr-studio"))  -- Hypr Studio (bar/widgets/panels/Hyprland editor)

-- Custom launcher helpers
hl.bind(mainMod .. " + CTRL + R", hl.dsp.exec_cmd("~/.local/bin/screen-record"))
hl.bind(mainMod .. " + CTRL + E", hl.dsp.exec_cmd("~/.local/bin/emoji-picker"))
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("~/.local/bin/region-record"))

-- Pop-up virtual Russian keyboard
hl.bind(mainMod .. " + SHIFT + K", hl.dsp.exec_cmd("~/.local/bin/ru-keyboard"))

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
end

-- Move active window to workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Move active window with mainMod + SHIFT + arrows
hl.bind(mainMod .. " + SHIFT + left", hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + up", hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + down", hl.dsp.window.move({ direction = "down" }))

-- Scratchpad workflow
hl.bind(mainMod .. " + SHIFT + minus", hl.dsp.window.move({ workspace = "special:scratchpad" }))
hl.bind(mainMod .. " + minus", hl.dsp.workspace.toggle_special("scratchpad"))

-- Scroll through workspaces with mainMod + SHIFT + scroll
hl.bind(mainMod .. " + SHIFT + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + SHIFT + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Screen zoom / magnifier
-- Hold SUPER + scroll wheel to zoom in/out around cursor
hl.bind(mainMod .. " + mouse_up", hl.dsp.exec_cmd("~/.config/hypr/scripts/zoom.sh in"))
hl.bind(mainMod .. " + mouse_down", hl.dsp.exec_cmd("~/.config/hypr/scripts/zoom.sh out"))

-- Keyboard zoom: SUPER + = (in), numpad +/- ; reset with SUPER + SHIFT + Z
hl.bind(mainMod .. " + equal", hl.dsp.exec_cmd("~/.config/hypr/scripts/zoom.sh in"), { locked = true, release = true })
hl.bind(mainMod .. " + KP_ADD", hl.dsp.exec_cmd("~/.config/hypr/scripts/zoom.sh in"), { locked = true, release = true })
hl.bind(mainMod .. " + KP_SUBTRACT", hl.dsp.exec_cmd("~/.config/hypr/scripts/zoom.sh out"), { locked = true, release = true })

hl.bind(mainMod .. " + SHIFT + Z", hl.dsp.exec_cmd("~/.config/hypr/scripts/zoom.sh reset"))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Multimedia and brightness keys
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5%"), { locked = true, repeating = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +5%"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set 5%+"), { locked = true, repeating = true })
