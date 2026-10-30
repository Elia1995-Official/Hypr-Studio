"""Shared neon skin for the Hypr tools (hyprglass-gui, hypr-studio): GTK4 CSS generated from
~/.config/hypr/theme.json, re-applied live when the Hyprland theme changes."""
import json
import os
import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gtk, Gdk, GLib, Gio


EXTRA_CSS = """
.nav { background: %(panel)s; border-right: 1px solid #%(border)s; padding: 10px 8px; }
.nav button { background: transparent; border: 1px solid transparent; border-radius: 10px; padding: 9px 14px; font-weight: 700; }
.nav button:hover { background: %(raised)s; border-color: #%(border)s; }
.nav button.current { background: #%(hl)s; border-color: #%(pr)s; color: #%(pr)s; }
.zone { background: %(panel)s; border: 1px solid #%(border)s; border-radius: 14px; padding: 10px; }
.linked button { border-radius: 0; margin: 0; }
.linked button:first-child { border-radius: 10px 0 0 10px; }
.linked button:last-child { border-radius: 0 10px 10px 0; }
button.mini { padding: 2px 7px; min-height: 0; min-width: 0; border-radius: 8px; }
.nav flowbox button { padding: 3px 9px; }
.zone-title { font-weight: 800; letter-spacing: 1px; color: #%(strong)s; }
.chip { background: %(raised)s; border: 1px solid #%(border)s; border-radius: 10px; padding: 6px 10px; }
.chip:selected, row:selected .chip { border-color: #%(pr)s; background: #%(hl)s; }
.chip.hiddenmod label { color: #%(border)s; }
.card { background: %(panel)s; border: 1px solid #%(border)s; border-radius: 14px; padding: 12px; }
.card:hover { border-color: #%(pr)s; }
.card-title { font-weight: 800; color: #%(pr)s; }
.dim-label { color: #8a9bb0; font-size: 12px; }
listbox, list { background: transparent; }
row { background: transparent; border-radius: 10px; }
row:selected { background: transparent; }
textview, textview text { background: %(bg0)s; color: #e6eef6; font-family: "JetBrainsMono Nerd Font Mono", monospace; font-size: 13px; }
.editor-wrap { border: 1px solid #%(border)s; border-radius: 12px; }
.console { background: %(bg0)s; border: 1px solid #%(border)s; border-radius: 10px; color: #%(sc)s; font-family: monospace; font-size: 12px; padding: 6px; }
headerbar { background: %(panel)s; border-bottom: 1px solid #%(border)s; }
"""


THEME_JSON = os.path.expanduser("~/.config/hypr/theme.json")
BASE_BG = (6, 13, 21)


def _rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _mix(a, b, t):
    """Hex colour a blended toward b by t, as '#rrggbb'."""
    c = [round(x + (y - x) * t) for x, y in zip(_rgb(a) if isinstance(a, str) else a, _rgb(b) if isinstance(b, str) else b)]
    return "#%02x%02x%02x" % tuple(c)


def skin_css():
    """Neon skin from the current Hyprland theme (same palette the bar, kitty and the rest use)."""
    try:
        p = json.load(open(THEME_JSON))
    except (OSError, ValueError):
        p = {}
    pr, sc = p.get("primary", "7dff4f"), p.get("second", "20c8ff")
    border, hl, dark = p.get("border", "2d661c"), p.get("hl", "1e4a14"), p.get("dark", "2a6b14")
    bg0 = "#%02x%02x%02x" % BASE_BG
    panel, raised = _mix(BASE_BG, pr, .06), _mix(BASE_BG, pr, .11)
    return """
@define-color accent_color #%(pr)s;
@define-color accent_bg_color #%(pr)s;
@define-color accent_fg_color #020509;
window, .background { background: radial-gradient(circle at 20%% 0%%, %(glow)s 0%%, %(bg0)s 62%%); color: #f4f8fc; }
label { color: #e6eef6; }
label.title-main { font-weight: 800; font-size: 15px; color: #%(pr)s; letter-spacing: 1px; }
label.status { color: #%(sc)s; font-size: 12px; }
expander { background: %(panel)s; border: 1px solid #%(border)s; border-radius: 12px; padding: 4px 10px; }
expander title { padding: 8px 4px; font-weight: 700; color: #%(strong)s; }
expander:checked { background: %(raised)s; border-color: #%(pr)s; }
button { background: %(panel)s; color: #f4f8fc; border: 1px solid #%(border)s; border-radius: 10px;
         padding: 5px 12px; box-shadow: none; background-image: none; }
button:hover { border-color: #%(pr)s; background: %(raised)s; }
button:active { background: #%(hl)s; }
button.suggested-action label, button:checked label { color: #020509; }
button.suggested-action, button:checked { background: #%(pr)s; color: #020509; border-color: #%(pr)s; font-weight: 700; }
entry, spinbutton { background: %(bg0)s; color: #f4f8fc; border: 1px solid #%(border)s; border-radius: 9px; box-shadow: none; }
entry:focus-within, spinbutton:focus-within { border-color: #%(pr)s; box-shadow: 0 0 0 2px alpha(#%(pr)s, .25); }
spinbutton button { border: none; border-radius: 0; background: transparent; }
dropdown > button { background: %(panel)s; }
popover > contents { background: %(raised)s; border: 1px solid #%(pr)s; border-radius: 12px; color: #f4f8fc; }
popover row:hover, popover row:selected { background: #%(hl)s; }
scale trough { background: #%(hl)s; border-radius: 6px; min-height: 6px; }
scale highlight { background: linear-gradient(90deg, #%(dark)s, #%(pr)s); border-radius: 6px; }
scale slider { background: #%(pr)s; border: 2px solid %(bg0)s; border-radius: 50%%; min-width: 14px; min-height: 14px;
               box-shadow: 0 0 8px alpha(#%(pr)s, .7); }
scale slider:hover { background: #%(strong)s; box-shadow: 0 0 12px #%(pr)s; }
switch { background: #%(hl)s; border-radius: 14px; border: 1px solid #%(border)s; }
switch:checked { background: #%(pr)s; border-color: #%(pr)s; }
switch slider { background: #f4f8fc; border-radius: 50%%; box-shadow: none; }
switch:checked slider { background: #020509; }
scrollbar slider { background: #%(border)s; border-radius: 8px; min-width: 6px; }
scrollbar slider:hover { background: #%(pr)s; }
scrollbar trough { background: transparent; }
separator { background: #%(border)s; min-height: 1px; }
colorbutton, button.color { padding: 2px; }
selection { background: #%(hl)s; color: #f4f8fc; }
*:focus-visible { outline-color: #%(pr)s; outline-offset: 1px; }
expander title *:focus-visible, expander title:focus-visible, expander arrow:focus-visible { outline: none; }
expander arrow, expander title > *, expander title:focus { outline: none; box-shadow: none; border: none; background: none; background-image: none; }
expander title:focus-visible { outline: none; }
expander title:hover label { color: #%(pr)s; }
""" % dict(pr=pr, sc=sc, border=border, hl=hl, dark=dark, strong=p.get("strong", pr), bg0=bg0, panel=panel,
           raised=raised, glow=_mix(BASE_BG, pr, .22)) + (EXTRA_CSS % dict(pr=pr, sc=sc, border=border, hl=hl, strong=p.get("strong", pr), bg0=bg0, panel=panel, raised=raised))


class Skin:
    """Applies skin_css() to the app and re-applies it live whenever theme.json changes (theme switch)."""

    def __init__(self):
        self.provider = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), self.provider,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_USER)
        try:
            Gtk.Settings.get_default().set_property("gtk-interface-color-scheme", 2)  # dark
        except TypeError:
            Gtk.Settings.get_default().set_property("gtk-application-prefer-dark-theme", True)
        self.apply()
        self.mon = Gio.File.new_for_path(THEME_JSON).monitor_file(Gio.FileMonitorFlags.NONE, None)
        self.mon.connect("changed", lambda *_: GLib.timeout_add(150, self.apply))

    def apply(self):
        self.provider.load_from_string(skin_css())
        return False


