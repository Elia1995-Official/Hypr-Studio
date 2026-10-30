# Hypr Studio — documentation

Everything built around the Hyprland "neon" rice on this machine (Arch, Hyprland 0.56.2 with **Lua config**, Quickshell 0.3.2,
dual monitors `DP-3` 7680×2160 and `HDMI-A-5` 1920×1080). Written 2026-10-30.

- [1. Architecture at a glance](#1-architecture-at-a-glance)
- [2. File map](#2-file-map)
- [3. Theme engine](#3-theme-engine)
- [4. Quickshell shell: bar, layout.json, panels](#4-quickshell-shell-bar-layoutjson-panels)
- [5. Hypr Studio (the editor)](#5-hypr-studio-the-editor)
- [6. Canvas editor reference](#6-canvas-editor-reference)
- [7. Hyprland configuration](#7-hyprland-configuration)
- [8. HyprGlass (liquid glass) and Kitty](#8-hyprglass-liquid-glass-and-kitty)
- [9. Keybinds](#9-keybinds)
- [10. Backup, git, restore](#10-backup-git-restore)
- [11. Troubleshooting and gotchas](#11-troubleshooting-and-gotchas)
- [12. Extending Hypr Studio](#12-extending-hypr-studio)

---

## 1. Architecture at a glance

```
              ┌───────────── theme.py (accent.sh) ─────────────┐
              │ 5 themes · wallpapers · app skins · VS Code pack │
              └──────┬───────────────┬──────────────────┬───────┘
                     │ writes        │ writes           │ OSC / reload
          ~/.config/hypr/theme.json   │ app configs      │ open terminals, mako, hyprland
                     │
   ┌─────────────────▼───────────────────┐
   │ Quickshell (shell.qml + Theme.qml)  │  bar · launcher · sidebar · tray menus
   │   reads layout.json  ◄───────────┐  │  user panels (createQmlObject)
   └──────────────────────────────────┼──┘
                                      │ writes layout.json, user/<name>/main.qml
                           ┌──────────┴──────────┐
                           │ Hypr Studio (GTK4)  │  Bar · Widgets · Panels · Canvas · Code · Hyprland
                           └──────────┬──────────┘
                                      │ hyprctl eval / reload, studio.lua
                           ┌──────────▼──────────┐        ┌───────────────────┐
                           │ Hyprland (Lua cfg)  │◄───────│ HyprGlass plugin  │ glass on kitty
                           └─────────────────────┘        └───────────────────┘
```

Key ideas:

- **Files are the interface.** Studio never talks to Quickshell directly: it writes `layout.json` / panel QML, and Quickshell
  hot-reloads them. Hyprland tweaks go through `hyprctl eval` (live) and `studio.lua` (persistent).
- **One palette.** `theme.json` (written by the theme engine) feeds Quickshell's `Theme.qml`, Hypr Studio's CSS (`neonskin.py`)
  and the canvas preview, so everything recolours together when you switch theme.

## 2. File map

| Path | What it is |
|---|---|
| `~/.local/bin/hypr-studio` | Main Studio app (GTK4/Python): Bar, Widgets, Panels, Code, Hyprland pages |
| `~/.local/lib/panelcanvas.py` | Canvas editor + QML generator (element types, drawing, undo/redo) |
| `~/.local/lib/neonskin.py` | Theme-aware GTK CSS shared by Studio and HyprGlass GUI |
| `~/.local/bin/hyprglass-gui` | Live HyprGlass settings (sliders, presets, saves to `glass.lua`) |
| `~/.local/share/applications/hypr-studio.desktop`, `hyprglass-gui.desktop` | Launcher entries |
| `~/.config/quickshell/shell.qml` | The shell: bar, launcher, sidebar, tray menu, panel loader |
| `~/.config/quickshell/Theme.qml` | Palette singleton (reads `theme.json`) |
| `~/.config/quickshell/BarSlot.qml`, `CustomModule.qml`, `GlassPill.qml` | Bar module slot, user-defined bar modules, pill container |
| `~/.config/quickshell/layout.json` | Bar layout + list of user panels (**edited by Studio**) |
| `~/.config/quickshell/user/<name>/main.qml` | A user panel (generated for canvas panels) |
| `~/.config/quickshell/user/<name>.panel.json` | Source of truth of a canvas panel |
| `~/.config/quickshell/user/.trash/` | Panels removed from Studio (never really deleted) |
| `~/.config/hypr/hyprland.lua` | Entry point: requires `monitors, workspaces, config, glass, devices, rules, binds, autostart` (+ `studio` once saved) |
| `~/.config/hypr/config.lua`, `rules.lua`, `binds.lua`, `autostart.lua` | Hyprland settings, window/layer rules, keybinds, startup |
| `~/.config/hypr/glass.lua` | HyprGlass presets + the kitty whitelist rule |
| `~/.config/hypr/glass-gui-presets.json` | Your own presets saved from HyprGlass GUI |
| `~/.config/hypr/studio.lua`, `studio.json` | Persistent Hyprland overrides from Studio ("Save permanently"); created on first save |
| `~/.config/hypr/theme.json`, `.accent`, `.wallpaper` | Current theme palette, theme name, wallpaper path |
| `~/.config/hypr/scripts/theme.py` (+ `accent.sh`) | Theme engine |
| `~/.config/hypr/scripts/wallpaper.sh`, `gen-wallpapers.py` | Wallpaper picker/switcher and generator |
| `~/.config/hypr/scripts/powermenu.sh`, `screenshot.sh`, `zoom.sh` | Utilities |
| `~/.local/share/hyprglass/src` | HyprGlass plugin source and `hyprglass.so` (third party, rebuildable) |
| `~/Pictures/Wallpapers/` | Wallpapers (neon, magenta, lime, amber, violet sets) |
| `~/hypr-studio/` | Git repo with copies of all the Studio files + this document |
| `~/Backups/hypr-studio/` | Dated tar.gz backups |

## 3. Theme engine

`~/.config/hypr/scripts/theme.py [pick|next|<name>]` (also `accent.sh`). Themes: **cyan, magenta, lime, amber, violet**.
One command switches:

- wallpaper (crossfade overlay in Quickshell, then hyprpaper) and the lock screen image;
- Quickshell colours (`theme.json` → `Theme.qml`, animated), Hyprland borders, mako, wofi, hyprlock;
- terminals (foot, alacritty, kitty — open terminals are recoloured live via OSC), btop, cava, GTK/KDE accent, Discord;
- icon theme `neon-folders` (folders recoloured to the accent) and a Thunar restart reopening the same folder;
- a full VS Code theme per rice theme (extension `elia1995.neon-themes`).

Wallpapers come from `gen-wallpapers.py` (palette-tinted). State files: `.accent` (name), `theme.json` (palette), `.wallpaper`.
Switch from Studio's sidebar buttons, or `Super+Alt+W` (picker) / `Super+Alt+N` (next).

`theme.json` keys: `primary, strong, soft, dark, second, border, subtle, hl` (hex without `#`).

## 4. Quickshell shell: bar, layout.json, panels

### 4.1 Bar layout

`layout.json` is watched; saving it re-lays the bar instantly:

```json
{
  "gap": 10,
  "left":   [{"type": "workspaces"}, {"type": "elsewhere"}, {"type": "mode"}],
  "center": [{"type": "start"}],
  "right":  [{"type": "tray"}, {"type": "network"}, {"type": "visualizer"}, {"type": "volume"}, {"type": "clock"}],
  "panels": [{"file": "showcase/main.qml", "enabled": true}]
}
```

Built-in module types: `workspaces, elsewhere, mode, start, tray, network, visualizer, volume, clock`.
Any entry can carry `"hidden": true`. `elsewhere` and `mode` also hide themselves when empty.

### 4.2 Custom bar modules

```json
{"type": "custom", "kind": "script", "icon": "󰔏", "command": "sensors | awk '/Package id 0/{print $4}'",
 "interval": 3, "color": "accent", "accent": false, "click": "kitty btop"}
```

| Field | Meaning |
|---|---|
| `kind` | `text` (static `text`), `script` (stdout of `command` every `interval` s), `clock` (`format`) |
| `icon` | Nerd Font glyph shown before the text |
| `color` | Icon colour: `accent`, `text`, or `#hex` |
| `accent` | `true` = highlighted pill |
| `click` | Shell command run on click |

Implemented by `BarSlot.qml` (picks the built-in component or `CustomModule.qml`) and `GlassPill.qml`.
In `shell.qml` each built-in module is a `Component { id: mod_<type> }`; the three zones are `Repeater`s over `layout.json`.

### 4.3 User panels

Each entry of `panels` is a QML file under `user/`. `shell.qml` loads them with a `Variants` + `QtObject` host:
the host reads the file with a `FileView` (watching it) and instantiates it with `Qt.createQmlObject(text, host, url)`.
Saving the file recreates the panel, so edits are live. Errors are logged as `user panel <file>: …` (see `quickshell log`).
Panel files use `import "../.."` to reach `Theme` and the other shell components, and are normal layer-shell `PanelWindow` QML.

## 5. Hypr Studio (the editor)

Open with **Super+Alt+S** (or the launcher entry "Hypr Studio"). Sidebar: Bar · Widgets · Panels · Canvas · Code · Hyprland,
plus theme buttons and a link to HyprGlass settings. The app skins itself from `theme.json`, live.

| Page | What you do there |
|---|---|
| **Bar** | Live preview strip + three zone lists. Drag chips (in the strip or the lists) to reorder or move between zones; ▲▼ buttons, hide (eye), remove. Properties panel for the selected module (custom modules: kind, icon, text/command, interval, colour, click). Changes save instantly |
| **Widgets** | Ten bar-module templates (custom clock, CPU temp/load, RAM, GPU temp, disk, weather, launcher button, label, blank script); add to left/center/right |
| **Panels** | Create a panel from a template (clock card, side info panel, toggle popup, blank), enable/disable, **Design** (opens the canvas), **Code**, remove (moves to `.trash`) |
| **Canvas** | Visual panel designer, see §6 |
| **Code** | Editor with a file list (user panels, `layout.json`, all `quickshell/*.qml`, `hypr/*.lua`). *Live apply* saves ~0.7 s after typing. QML saves hot-reload the panel; Lua saves run `hyprctl reload`. A console shows errors |
| **Hyprland** | Sliders for gaps, border, rounding, opacity, shadow, blur (applied live with `hyprctl eval`); *Save permanently* writes `studio.lua`; *Reset* removes the overrides; searchable keybind list read from `binds.lua` |

## 6. Canvas editor reference

Pick or create a panel at the top. The canvas draws the panel (card + items) with the real theme colours and live
clock/script values; each change is saved ~0.35 s later and appears on the desktop.

**Interaction**

- Click an item to select; drag to move; drag its 8 handles to resize.
- The 8 **yellow handles** on the panel border resize the panel itself (left/top edges keep items in place on screen).
- Arrow keys nudge (Shift = 10 px); `Del` deletes; `Ctrl+D` duplicates.
- **Undo `Ctrl+Z`, redo `Ctrl+Shift+Z` / `Ctrl+Y`** (also the ↶ ↷ buttons); up to 200 steps; drags and rapid edits are grouped.
- Grid: show/hide switch + cell size; **Snap** switch snaps to the grid; magnetic pink guides snap to panel/item edges and centres.
- "Align to panel" buttons: left, centre H, right, top, centre V, bottom, centre both.
- Layers list: bring forward / send back, duplicate, delete.

**Panel settings:** width, height, monitor, position (9 anchors) + margins, layer (`bottom` / `top` / `overlay`),
card on/off, card radius, opacity, border.

**Elements**

| Element | What it does | Default size | Properties |
|---|---|---|---|
| 󰉿 `text` | Static label. | 160×28 | `text`, `size`, `weight`, `color`, `align` |
|  `clock` | Live clock (Qt `formatDateTime` format, e.g. `HH:mm`, `dddd d MMMM`). | 200×60 | `format`, `size`, `weight`, `color`, `align` |
| 󰆍 `script` | Shows a shell command's stdout, refreshed every N seconds. | 160×28 | `command`, `interval`, `prefix`, `suffix`, `size`, `weight`, `color`, `align` |
| 󰝤 `rect` | Rounded rectangle (fill + border). | 120×60 | `color`, `opacity`, `radius`, `border`, `bcolor` |
| 󰹞 `bar` | Horizontal progress bar fed by a command that prints 0-100. | 200×10 | `command`, `interval`, `color`, `track`, `radius` |
| 󰐊 `button` | Clickable button that runs a shell command. | 120×34 | `text`, `click`, `size`, `color`, `bg`, `radius` |
| 󰋩 `image` | Image from a file path. | 96×96 | `path` |
| 󰇘 `line` | Thin divider line. | 160×2 | `color`, `opacity` |
| 󰝦 `circle` | Circle / ellipse with fill and border. | 64×64 | `color`, `opacity`, `border`, `bcolor` |
| 󰀻 `icon` | Large Nerd Font glyph (picker included). | 48×48 | `text`, `size`, `color` |
| 󰦖 `gauge` | Ring gauge fed by a command printing 0-100. | 96×96 | `command`, `interval`, `thickness`, `size`, `suffix`, `color`, `track` |
| 󰄧 `graph` | Rolling line chart of a command's numeric output. | 200×60 | `command`, `interval`, `points`, `max`, `color`, `fill` |
| 󰹞 `slider` | Draggable slider: one command reads the value, another sets it (`{}` = value). | 200×24 | `get`, `set`, `interval`, `color`, `track` |
| 󰆍 `output` | Multi-line command output, optionally wrapped. | 240×90 | `command`, `interval`, `size`, `color`, `wrap` |
| 󰥔 `analogclock` | Analog clock with hour ticks and a second hand. | 120×120 | `color`, `hands`, `ticks` |

Common to all: `x, y, w, h` (px in panel space). Text-like elements also support `align` (left / centre / right buttons),
`size`, `weight`. Colour properties take a **role** (follows the theme) or a `#hex`:

| Colour role | QML binding |
|---|---|
| `accent` | `Theme.neon` |
| `strong` | `Theme.neonStrong` |
| `soft` | `Theme.neonSoft` |
| `text` | `Theme.textPrimary` |
| `secondary` | `Theme.textSecondary` |
| `muted` | `Theme.textMuted` |
| `success` | `Theme.success` |
| `warning` | `Theme.warning` |
| `danger` | `Theme.danger` |
| `panel` | `Theme.panel` |
| `raised` | `Theme.panelRaised` |

**Files per panel:** `user/<name>.panel.json` (source — safe to edit by hand) and `user/<name>/main.qml`
(generated; starts with a "Generated by Hypr Studio" comment and is overwritten on each canvas save —
if you edit the QML in the Code page, the canvas warns you).

## 7. Hyprland configuration

- Lua config: `hyprland.lua` requires the other modules in order. After editing run `hyprctl reload` (`Super+Shift+C`);
  errors: `hyprctl configerrors`.
- Appearance defaults live in `config.lua` (gaps 5/10, gradient border 2, rounding 25, blur size 10 / 4 passes /
  vibrancy 0.45, inactive opacity 0.94, dim 0.08, jelly/overshoot animation curves).
- `rules.lua`: float rules, workspace assignments (Steam/Discord/OBS/Spotify → 2, games → 5, **kitty → 1**),
  layer blur rules (wofi, rofi, mako, quickshell…), `kitty-glass` (rim border, no compositor opacity), `wallfade-noanim`.
- Live changes from Studio use `hyprctl eval 'hl.config({ ... })'` (the old `hyprctl keyword` does not work with Lua).
  They vanish on reload unless saved to `studio.lua`, which `hyprland.lua` requires last.
- Startup (`autostart.lua`): hyprpaper, polkit, quickshell, mako, hypridle, Steam, Telegram, vesktop, `sleep 2 && kitty`,
  and the HyprGlass loader (`sleep 3; hyprctl plugin load … && hyprctl reload`).

## 8. HyprGlass (liquid glass) and Kitty

- **Plugin:** `hyprnux/hyprglass`, branch `hyprland-0.56`, built in `~/.local/share/hyprglass/src`:

  ```bash
  cd ~/.local/share/hyprglass/src
  CPLUS_INCLUDE_PATH=$HOME/.local/share/hyprglass/inc make     # inc/hyprland -> /usr/include/hyprland
  hyprctl plugin load ~/.local/share/hyprglass/src/hyprglass.so
  hyprctl hyprglass status
  ```

  The private include path is needed because `/usr/local/include/hyprland` is a stale copy that clashes with the packaged
  headers. After a Hyprland update the plugin may report "Paused": rebuild it (matching branch).
- **Loading:** `hl.plugin.load()` from Lua silently does nothing here, so `autostart.lua` loads the `.so` with `hyprctl` and
  reloads; `glass.lua` then configures it (`if hl.plugin.hyprglass then …`).
- **Scope:** `enabled = false` globally + rule `tag = "+hyprglass_enabled"` for class `kitty` = glass only on Kitty.
  The bar, launcher and notifications keep the normal compositor blur.
- **Presets:** edit with **HyprGlass GUI** (`Super+Alt+G`, also `Super+G`): live sliders, built-in/own presets, *Save to glass.lua*
  (backup `glass.lua.bak`). Built-in presets: "Apple (pomme)", "Lens edge (old kitty)", "Clear pane", "Subtle", "Glass block".
- **Kitty:** `~/.config/kitty/kitty.conf` (+ generated `neon-theme.conf`): transparent background (`background_opacity` 0.22),
  powerline tabs, scrollbar, cursor trail. Kitty is the default terminal (`Super+Return`).

## 9. Keybinds

`mainMod` = Super. Rice-related binds (the full list is on Studio's Hyprland page):

| Keys | Action |
|---|---|
| `Super+Return` | Terminal (kitty) |
| `Super+R` | Launcher |
| `Super+W` / `Super+Shift+W` | Wallpaper picker / next |
| `Super+Alt+W` / `Super+Alt+N` | Theme picker / next theme |
| `Super+Alt+S` | **Hypr Studio** |
| `Super+Alt+G`, `Super+G` | **HyprGlass settings** |
| `Super+Shift+C` | `hyprctl reload` |
| `Super+Shift+B` | Restart Quickshell |
| `Super+Shift+E` | Open `~/.config/hypr` in VS Code |
| `Super+Escape` | Power menu |
| `Super+L`, `Super+Alt+L` | Lock |
| `Print`, `Shift+Print` | Screenshot region / screen |

In Studio's canvas: `Ctrl+Z`, `Ctrl+Shift+Z` / `Ctrl+Y`, `Ctrl+D`, `Del`, arrows (+Shift).

## 10. Backup, git, restore

Repo: `~/hypr-studio` (copies of the live files listed in `MANIFEST`). Live files are **not** symlinked.

```bash
~/hypr-studio/sync.sh        # copy live files into the repo and commit if changed
~/hypr-studio/sync.sh -b     # ...plus a dated ~/Backups/hypr-studio/hypr-studio_<date>_<time>.tar.gz
~/hypr-studio/sync.sh -r     # restore repo files over the live ones (asks first)
git -C ~/hypr-studio log --oneline
```

Add files to track by appending paths (relative to `$HOME`, globs allowed) to `MANIFEST`.
Not covered: the rest of the rice (theme engine, kitty, mako…); older config backups are in `~/.config/hypr/_archive/`.
The SDDM theme update needs `sudo ~/.config/hypr/install-rice-system.sh` (run by you).

## 11. Troubleshooting and gotchas

| Symptom | Cause / fix |
|---|---|
| Bar broken after an edit | `quickshell log`; restore `shell.qml` from `~/.config/quickshell/backup/shell.qml.pre-layout` or the repo; restart with `Super+Shift+B` |
| New panel does not appear | Check `quickshell log` for `user panel <file>:`. The panel must be listed in `layout.json` → `panels` and enabled |
| "File name case mismatch" | Qt caches a folder's file list, so a file added later to an already-loaded folder fails. That is why panels are loaded from text (`createQmlObject`) and live in their own folder |
| Panel hidden behind windows | Layer is `bottom`; set `top` / `overlay` on the Canvas page |
| Glass not showing on Kitty | `hyprctl plugin list`, `hyprctl hyprglass status`; `hyprctl reload`; rebuild after Hyprland updates |
| `hyprctl keyword …` "can't work with non-legacy parsers" | Use `hyprctl eval 'hl.config({...})'` |
| `hl.plugin.load` does nothing | Known here; use the `autostart.lua` loader |
| Workspace state empty | The I3 IPC module does not work on Hyprland; the bar polls `hyprctl` every 400 ms |
| Studio edits not applying | Python files need Studio restarted (close and reopen); QML and `layout.json` apply live |
| Pink/black icons | `Quickshell.iconPath(name, true)` returns "" when missing → letter-tile fallback |

## 12. Extending Hypr Studio

**Add a canvas element type** (`panelcanvas.py`):

1. `DEFAULT_ITEMS["mytype"]` — default size/props; `ITEM_ICONS["mytype"]` — toolbox glyph.
2. `SCHEMA["mytype"]` — property rows `(key, label, kind, extra)`; kinds: `str, int, float, bool, choice, color, glyph`.
3. `gen_qml()` — add an `elif t == "mytype":` branch that appends QML lines (use `runner()` for command-driven items).
4. `draw_item()` — add an `elif t == "mytype":` branch drawing a cairo preview.
5. Test: add one in the canvas, check `user/<name>/main.qml` and `quickshell log`.

**Add a built-in bar module:** wrap it in `Component { id: mod_<type> … }` inside the bar `PanelWindow` in `shell.qml`,
add it to `modComponents` (and `modVisible` if it can hide itself), then add the type to `BUILTIN` in `hypr-studio`.

**Add a Hyprland slider:** append `("section.key", "Label", min, max, step, "int" | "float")` to `HYPR_SECTIONS` in `hypr-studio`.

**Add a bar widget template:** append to `WIDGET_TEMPLATES` in `hypr-studio`.

**Add a panel template:** append to `PANEL_TEMPLATES` in `hypr-studio` (the QML must start with `import "../.."`).

After editing Python files run `python3 -m py_compile <file>`, then `~/hypr-studio/sync.sh -b` to snapshot.
