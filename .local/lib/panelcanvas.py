"""Canvas editor for Quickshell panels (used by hypr-studio).

A panel is described by ~/.config/quickshell/user/<name>.panel.json (the source of truth) and compiled to
~/.config/quickshell/user/<name>.qml, which Quickshell hot-reloads: what you see on the real desktop is the preview.
"""
import hashlib
import json
import math
import os
import subprocess
import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gtk, Gdk, GLib, GObject, Pango, PangoCairo

HOME = os.path.expanduser("~")
USER_DIR = HOME + "/.config/quickshell/user"
THEME_JSON = HOME + "/.config/hypr/theme.json"
FONT = "IosevkaTerm Nerd Font"

ROLES = {  # name -> (QML expression, fallback hex for the preview)
    "accent": ("Theme.neon", None), "strong": ("Theme.neonStrong", None), "soft": ("Theme.neonSoft", None),
    "text": ("Theme.textPrimary", "f4f8fc"), "secondary": ("Theme.textSecondary", "a5b5c5"),
    "muted": ("Theme.textMuted", "617384"), "success": ("Theme.success", "00efa5"),
    "warning": ("Theme.warning", "ffb84a"), "danger": ("Theme.danger", "ff405c"),
    "panel": ("Theme.panel", "060d15"), "raised": ("Theme.panelRaised", "08131f"),
}
GLYPHS = ["󰻠", "󰍛", "󰋊", "󰔏", "󰢮", "󰈀", "󰤮", "", "", "󰖐", "󰐊", "󰆍", "󰉿", "󰕮", "󰏗", "󰖲", "󰅩", "󰋩", "󰦟", "󰈈", "󰆴", "󰙲", "󱄄", "󰂵", "", ""]
POSITIONS = ["top-left", "top", "top-right", "left", "center", "right", "bottom-left", "bottom", "bottom-right"]
LAYERS = ["bottom", "top", "overlay"]

DEFAULT_ITEMS = {
    "text": dict(w=160, h=28, text="Label", size=16, weight="700", color="text", align="left"),
    "clock": dict(w=200, h=60, format="HH:mm", size=44, weight="800", color="strong", align="left"),
    "script": dict(w=160, h=28, command="cut -d' ' -f1 /proc/loadavg", interval=3, size=18, weight="700",
                   color="accent", align="left", prefix="", suffix=""),
    "rect": dict(w=120, h=60, color="accent", opacity=0.16, radius=12, border=1, bcolor="accent"),
    "bar": dict(w=200, h=10, command="free | awk '/Mem/{printf \"%d\", $3/$2*100}'", interval=5, color="accent",
                track="muted", radius=5),
    "button": dict(w=120, h=34, text="Run", click="kitty", size=14, color="text", bg="accent", radius=10),
    "image": dict(w=96, h=96, path=""),
    "line": dict(w=160, h=2, color="accent", opacity=0.6),
    "circle": dict(w=64, h=64, color="accent", opacity=0.18, border=2, bcolor="accent"),
    "icon": dict(w=48, h=48, text="󰻠", size=32, color="accent"),
    "gauge": dict(w=96, h=96, command="cut -d' ' -f1 /proc/loadavg | awk '{printf \"%d\", $1*10}'", interval=3, color="accent",
                  track="muted", thickness=8, size=18, suffix="%"),
    "graph": dict(w=200, h=60, command="free | awk '/Mem/{printf \"%d\", $3/$2*100}'", interval=2, color="accent", fill=0.18, points=60),
    "slider": dict(w=200, h=24, get="wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf \"%d\", $2*100}'",
                   set="wpctl set-volume @DEFAULT_AUDIO_SINK@ {}%", interval=3, color="accent", track="muted"),
    "output": dict(w=240, h=90, command="uptime -p", interval=10, size=13, color="secondary", wrap=True),
    "analogclock": dict(w=120, h=120, color="accent", hands="text", ticks=True),
}

# type -> [(key, label, kind, extra)]
SCHEMA = {
    "text": [("text", "Text", "str", None), ("size", "Size", "int", (6, 160)), ("weight", "Weight", "choice", ["400", "600", "700", "800"]),
             ("color", "Colour", "color", None), ("align", "Align", "choice", ["left", "center", "right"])],
    "clock": [("format", "Format (Qt)", "str", None), ("size", "Size", "int", (6, 160)), ("weight", "Weight", "choice", ["400", "600", "700", "800"]),
              ("color", "Colour", "color", None), ("align", "Align", "choice", ["left", "center", "right"])],
    "script": [("command", "Command", "str", None), ("interval", "Every (s)", "int", (1, 3600)),
               ("prefix", "Prefix", "str", None), ("suffix", "Suffix", "str", None),
               ("size", "Size", "int", (6, 160)), ("weight", "Weight", "choice", ["400", "600", "700", "800"]),
               ("color", "Colour", "color", None), ("align", "Align", "choice", ["left", "center", "right"])],
    "rect": [("color", "Fill", "color", None), ("opacity", "Fill opacity", "float", (0, 1)), ("radius", "Radius", "int", (0, 200)),
             ("border", "Border width", "int", (0, 12)), ("bcolor", "Border colour", "color", None)],
    "bar": [("command", "Command (prints 0-100)", "str", None), ("interval", "Every (s)", "int", (1, 3600)),
            ("color", "Fill", "color", None), ("track", "Track", "color", None), ("radius", "Radius", "int", (0, 50))],
    "button": [("text", "Label", "str", None), ("click", "On click (shell)", "str", None), ("size", "Size", "int", (6, 80)),
               ("color", "Text colour", "color", None), ("bg", "Background", "color", None), ("radius", "Radius", "int", (0, 60))],
    "image": [("path", "Image path", "str", None)],
    "line": [("color", "Colour", "color", None), ("opacity", "Opacity", "float", (0, 1))],
    "circle": [("color", "Fill", "color", None), ("opacity", "Fill opacity", "float", (0, 1)), ("border", "Border width", "int", (0, 12)),
               ("bcolor", "Border colour", "color", None)],
    "icon": [("text", "Glyph", "glyph", None), ("size", "Size", "int", (6, 200)), ("color", "Colour", "color", None)],
    "gauge": [("command", "Command (prints 0-100)", "str", None), ("interval", "Every (s)", "int", (1, 3600)),
              ("thickness", "Ring thickness", "int", (1, 40)), ("size", "Value size", "int", (6, 80)), ("suffix", "Suffix", "str", None),
              ("color", "Ring", "color", None), ("track", "Track", "color", None)],
    "graph": [("command", "Command (prints a number)", "str", None), ("interval", "Every (s)", "int", (1, 3600)),
              ("points", "History points", "int", (10, 300)), ("max", "Max value (0 = auto)", "int", (0, 100000)), ("color", "Line", "color", None), ("fill", "Area opacity", "float", (0, 1))],
    "slider": [("get", "Read command (0-100)", "str", None), ("set", "Set command ({} = value)", "str", None),
               ("interval", "Re-read every (s)", "int", (1, 3600)), ("color", "Fill", "color", None), ("track", "Track", "color", None)],
    "output": [("command", "Command (multi-line)", "str", None), ("interval", "Every (s)", "int", (1, 3600)),
               ("size", "Size", "int", (6, 80)), ("color", "Colour", "color", None), ("wrap", "Wrap lines", "bool", None)],
    "analogclock": [("color", "Accent", "color", None), ("hands", "Hands colour", "color", None), ("ticks", "Hour ticks", "bool", None)],
}
ITEM_ICONS = {"text": "󰉿", "clock": "", "script": "󰆍", "rect": "󰝤", "bar": "󰹞", "button": "󰐊", "image": "󰋩", "line": "󰇘", "circle": "󰝦", "icon": "󰀻", "gauge": "󰦖",
              "graph": "󰄧", "slider": "󰹞", "output": "󰆍", "analogclock": "󰥔"}


# ---------------------------------------------------------------- model + QML generation
def monitor_names():
    try:
        return [m["name"] for m in json.loads(subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True).stdout)]
    except (ValueError, OSError):
        return []


def new_doc(name):
    mons = monitor_names()
    return {
        "name": name, "monitor": "DP-3" if "DP-3" in mons else (mons[0] if mons else ""), "width": 320, "height": 140, "position": "bottom-right", "margin_x": 40, "margin_y": 40,
        "layer": "bottom", "card": True, "card_radius": 22, "card_opacity": 0.78, "card_border": True,
        "generated_hash": "",
        "items": [
            dict(type="clock", x=24, y=18, **{k: v for k, v in DEFAULT_ITEMS["clock"].items()}),
            dict(type="text", x=24, y=86, **dict(DEFAULT_ITEMS["text"], text="Hello from the canvas", size=14, color="secondary", w=270)),
        ],
    }


def qs(s):
    return json.dumps(str(s), ensure_ascii=False)


def color_expr(c, alpha=None):
    c = str(c)
    if c in ROLES:
        base = ROLES[c][0]
        return base if alpha is None else "Theme.alpha(%s, %s)" % (base, alpha)
    c = c if c.startswith("#") else "#" + c
    return qs(c) if alpha is None else "Qt.alpha(%s, %s)" % (qs(c), alpha)


def gen_qml(doc):
    name = doc["name"]
    pos = doc.get("position", "bottom-right")
    anchors, margins = [], []
    if "top" in pos:
        anchors.append("top: true")
        margins.append("top: %d" % doc.get("margin_y", 0))
    if "bottom" in pos:
        anchors.append("bottom: true")
        margins.append("bottom: %d" % doc.get("margin_y", 0))
    if "left" in pos:
        anchors.append("left: true")
        margins.append("left: %d" % doc.get("margin_x", 0))
    if "right" in pos:
        anchors.append("right: true")
        margins.append("right: %d" % doc.get("margin_x", 0))
    items = doc["items"]
    out = ["// Generated by Hypr Studio (Canvas). Edit visually: changes made here are overwritten on save.",
           "import QtQuick", "import Quickshell", "import Quickshell.Io", "import Quickshell.Wayland", 'import "../.."', "",
           "PanelWindow {", "    id: win"]
    if anchors:
        out.append("    anchors { %s }" % "; ".join(anchors))
        out.append("    margins { %s }" % "; ".join(margins))
    if doc.get("monitor"):
        out.append("    screen: { var m = Quickshell.screens.filter(function(s) { return s.name === %s }); return m.length ? m[0] : Quickshell.screens[0] }"
                   % qs(doc["monitor"]))
    out += ["    implicitWidth: %d" % doc["width"], "    implicitHeight: %d" % doc["height"],
            '    color: "transparent"', "    exclusionMode: ExclusionMode.Ignore",
            "    WlrLayershell.layer: WlrLayer.%s" % {"bottom": "Bottom", "top": "Top", "overlay": "Overlay"}[doc.get("layer", "bottom")],
            '    WlrLayershell.namespace: "studio-%s"' % name, ""]
    if any(i["type"] in ("clock", "analogclock") for i in items):
        out += ["    SystemClock { id: clk; precision: SystemClock.Seconds }", ""]
    if doc.get("card", True):
        bd = ("        border.width: 1\n        border.color: %s\n" % color_expr("accent", 0.55)) if doc.get("card_border", True) else ""
        out += ["    Rectangle {", "        anchors.fill: parent", "        radius: %d" % doc.get("card_radius", 22),
                "        color: Theme.alpha(Theme.panel, %s)" % doc.get("card_opacity", 0.78), bd.rstrip("\n"), "    }", ""]
    def runner(n, cmd, interval, done):
        return ["    Process {", "        id: p%d" % n, '        command: ["sh", "-c", %s]' % qs(cmd),
                "        stdout: StdioCollector { onStreamFinished: %s }" % done, "    }",
                "    Timer { interval: %d; running: true; repeat: true; triggeredOnStart: true; onTriggered: { p%d.running = false; p%d.running = true } }"
                % (max(1, interval) * 1000, n, n)]

    for n, it in enumerate(items):
        t = it["type"]
        geo = "x: %d; y: %d; width: %d; height: %d" % (it["x"], it["y"], it["w"], it["h"])
        al = {"left": "Text.AlignLeft", "center": "Text.AlignHCenter", "right": "Text.AlignRight"}.get(it.get("align", "left"))
        if t in ("text", "clock", "script"):
            txt = {"text": qs(it.get("text", "")),
                   "clock": "Qt.formatDateTime(clk.date, %s)" % qs(it.get("format", "HH:mm")),
                   "script": "%s + s%d.out + %s" % (qs(it.get("prefix", "")), n, qs(it.get("suffix", "")))}[t]
            out += ["    Text {", "        id: s%d" % n]
            if t == "script":
                out.append('        property string out: ""')
            out += ["        " + geo, "        text: " + txt, "        color: " + color_expr(it.get("color", "text")),
                    "        font.family: Theme.fontFamily", "        font.pixelSize: %d" % it.get("size", 16),
                    "        font.weight: %s" % it.get("weight", "700"), "        horizontalAlignment: " + al,
                    "        verticalAlignment: Text.AlignVCenter", "        elide: Text.ElideRight", "    }"]
            if t == "script":
                out += ["    Process {", "        id: p%d" % n, '        command: ["sh", "-c", %s]' % qs(it.get("command", "true")),
                        "        stdout: StdioCollector { onStreamFinished: s%d.out = this.text.trim() }" % n, "    }",
                        "    Timer { interval: %d; running: true; repeat: true; triggeredOnStart: true; onTriggered: { p%d.running = false; p%d.running = true } }"
                        % (max(1, it.get("interval", 3)) * 1000, n, n)]
        elif t == "rect":
            out += ["    Rectangle {", "        " + geo, "        radius: %d" % it.get("radius", 0),
                    "        color: " + color_expr(it.get("color", "accent"), it.get("opacity", 0.16)),
                    "        border.width: %d" % it.get("border", 0), "        border.color: " + color_expr(it.get("bcolor", "accent")), "    }"]
        elif t == "bar":
            out += ["    Rectangle {", "        id: b%d" % n, "        property real value: 0", "        " + geo,
                    "        radius: %d" % it.get("radius", 5), "        color: " + color_expr(it.get("track", "muted"), 0.35),
                    "        Rectangle { width: parent.width * Math.max(0, Math.min(100, parent.value)) / 100; height: parent.height; radius: parent.radius; color: %s }"
                    % color_expr(it.get("color", "accent")),
                    "        Behavior on value { NumberAnimation { duration: 400 } }", "    }",
                    "    Process {", "        id: p%d" % n, '        command: ["sh", "-c", %s]' % qs(it.get("command", "echo 0")),
                    "        stdout: StdioCollector { onStreamFinished: b%d.value = parseFloat(this.text) || 0 }" % n, "    }",
                    "    Timer { interval: %d; running: true; repeat: true; triggeredOnStart: true; onTriggered: { p%d.running = false; p%d.running = true } }"
                    % (max(1, it.get("interval", 5)) * 1000, n, n)]
        elif t == "button":
            out += ["    Rectangle {", "        id: b%d" % n, "        " + geo, "        radius: %d" % it.get("radius", 10),
                    "        color: m%d.containsMouse ? %s : %s" % (n, color_expr(it.get("bg", "accent"), 0.32), color_expr(it.get("bg", "accent"), 0.18)),
                    "        border.width: 1", "        border.color: " + color_expr(it.get("bg", "accent"), 0.7),
                    "        Behavior on color { ColorAnimation { duration: 120 } }",
                    "        Text { anchors.centerIn: parent; text: %s; color: %s; font.family: Theme.fontFamily; font.pixelSize: %d; font.weight: 700 }"
                    % (qs(it.get("text", "")), color_expr(it.get("color", "text")), it.get("size", 14)),
                    "        MouseArea { id: m%d; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { c%d.running = false; c%d.running = true } }"
                    % (n, n, n), "    }",
                    '    Process { id: c%d; command: ["sh", "-c", %s] }' % (n, qs(it.get("click", "true")))]
        elif t == "line":
            out += ["    Rectangle {", "        " + geo, "        radius: Math.min(width, height) / 2",
                    "        color: " + color_expr(it.get("color", "accent"), it.get("opacity", 0.6)), "    }"]
        elif t == "circle":
            out += ["    Rectangle {", "        " + geo, "        radius: Math.min(width, height) / 2",
                    "        color: " + color_expr(it.get("color", "accent"), it.get("opacity", 0.18)),
                    "        border.width: %d" % it.get("border", 0), "        border.color: " + color_expr(it.get("bcolor", "accent")), "    }"]
        elif t == "icon":
            out += ["    Text {", "        " + geo, "        text: " + qs(it.get("text", "")), "        color: " + color_expr(it.get("color", "accent")),
                    "        font.family: Theme.iconFamily", "        font.pixelSize: %d" % it.get("size", 32),
                    "        horizontalAlignment: Text.AlignHCenter", "        verticalAlignment: Text.AlignVCenter", "    }"]
        elif t == "gauge":
            out += ["    Item {", "        id: g%d" % n, "        property real value: 0", "        " + geo,
                    "        onValueChanged: cv%d.requestPaint()" % n,
                    "        Behavior on value { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }",
                    "        Canvas {", "            id: cv%d" % n, "            anchors.fill: parent",
                    "            property color ringColor: " + color_expr(it.get("color", "accent")),
                    "            property color trackColor: " + color_expr(it.get("track", "muted"), 0.35),
                    "            onRingColorChanged: requestPaint()", "            onTrackColorChanged: requestPaint()",
                    "            onPaint: {", "                var ctx = getContext(\"2d\"); ctx.reset()",
                    "                var lw = %d; var r = Math.min(width, height) / 2 - lw / 2 - 1; var cx = width / 2; var cy = height / 2" % it.get("thickness", 8),
                    "                ctx.lineWidth = lw; ctx.lineCap = \"round\"",
                    "                ctx.strokeStyle = trackColor; ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke()",
                    "                ctx.strokeStyle = ringColor; ctx.beginPath()",
                    "                ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0, Math.min(100, g%d.value)) / 100); ctx.stroke()" % n,
                    "            }", "        }",
                    "        Text { anchors.centerIn: parent; text: Math.round(g%d.value) + %s; color: Theme.textPrimary; font.family: Theme.fontFamily; font.pixelSize: %d; font.weight: 800 }"
                    % (n, qs(it.get("suffix", "")), it.get("size", 18)), "    }"]
            out += runner(n, it.get("command", "echo 0"), it.get("interval", 3), "g%d.value = parseFloat(this.text) || 0" % n)
        elif t == "graph":
            out += ["    Item {", "        id: gr%d" % n, "        property var hist: []", "        " + geo,
                    "        Canvas {", "            id: cv%d" % n, "            anchors.fill: parent",
                    "            property color lineColor: " + color_expr(it.get("color", "accent")),
                    "            property color areaColor: " + color_expr(it.get("color", "accent"), it.get("fill", 0.18)),
                    "            onPaint: {", "                var ctx = getContext(\"2d\"); ctx.reset()", "                var h = gr%d.hist; if (h.length < 2) return" % n,
                    "                var mx = %s; var step = width / (%d - 1)" % ("%d" % it["max"] if it.get("max", 0) > 0 else "Math.max.apply(null, h.concat([1]))", it.get("points", 60)),
                    "                var x0 = width - (h.length - 1) * step",
                    "                ctx.beginPath(); for (var i = 0; i < h.length; i++) { var y = height - (h[i] / mx) * (height - 2) - 1; if (i === 0) ctx.moveTo(x0, y); else ctx.lineTo(x0 + i * step, y) }",
                    "                ctx.lineWidth = 2; ctx.lineJoin = \"round\"; ctx.strokeStyle = lineColor; ctx.stroke()",
                    "                ctx.lineTo(width, height); ctx.lineTo(x0, height); ctx.closePath(); ctx.fillStyle = areaColor; ctx.fill()",
                    "            }", "        }", "    }"]
            out += runner(n, it.get("command", "echo 0"), it.get("interval", 2),
                          "{ var v = parseFloat(this.text) || 0; var h = gr%d.hist.length ? gr%d.hist.concat([v]) : new Array(%d).fill(v); if (h.length > %d) h = h.slice(h.length - %d); gr%d.hist = h; cv%d.requestPaint() }"
                          % (n, n, it.get("points", 60), it.get("points", 60), it.get("points", 60), n, n))
        elif t == "slider":
            out += ["    Rectangle {", "        id: sl%d" % n, "        property real value: 0", "        " + geo,
                    "        radius: height / 2", "        color: " + color_expr(it.get("track", "muted"), 0.3),
                    "        Rectangle { width: Math.max(parent.height, parent.width * Math.max(0, Math.min(100, parent.value)) / 100); height: parent.height; radius: height / 2; color: %s }"
                    % color_expr(it.get("color", "accent")),
                    "        Behavior on value { enabled: !ma%d.pressed; NumberAnimation { duration: 250 } }" % n,
                    "        MouseArea {", "            id: ma%d" % n, "            anchors.fill: parent", "            cursorShape: Qt.PointingHandCursor",
                    "            function setFrom(mx) { sl%d.value = Math.max(0, Math.min(100, mx / width * 100)) }" % n,
                    "            onPressed: function(e) { setFrom(e.x) }", "            onPositionChanged: function(e) { if (pressed) setFrom(e.x) }",
                    "            onReleased: { w%d.command = [\"sh\", \"-c\", %s.replace(\"{}\", Math.round(sl%d.value))]; w%d.running = false; w%d.running = true }"
                    % (n, qs(it.get("set", "true")), n, n, n), "        }", "    }",
                    "    Process { id: w%d }" % n]
            out += runner(n, it.get("get", "echo 0"), it.get("interval", 3), "if (!ma%d.pressed) sl%d.value = parseFloat(this.text) || 0" % (n, n))
        elif t == "output":
            out += ["    Text {", "        id: o%d" % n, "        " + geo, "        text: \"\"", "        color: " + color_expr(it.get("color", "secondary")),
                    "        font.family: Theme.fontFamily", "        font.pixelSize: %d" % it.get("size", 13),
                    "        wrapMode: Text.%s" % ("Wrap" if it.get("wrap", True) else "NoWrap"), "        elide: Text.ElideRight", "        clip: true", "    }"]
            out += runner(n, it.get("command", "true"), it.get("interval", 10), "o%d.text = this.text.trim()" % n)
        elif t == "analogclock":
            out += ["    Canvas {", "        id: ac%d" % n, "        " + geo,
                    "        property color accentColor: " + color_expr(it.get("color", "accent")),
                    "        property color handColor: " + color_expr(it.get("hands", "text")),
                    "        Connections { target: clk; function onDateChanged() { ac%d.requestPaint() } }" % n,
                    "        onAccentColorChanged: requestPaint()", "        onHandColorChanged: requestPaint()",
                    "        onPaint: {", "            var ctx = getContext(\"2d\"); ctx.reset()",
                    "            var r = Math.min(width, height) / 2 - 3; var cx = width / 2; var cy = height / 2; var d = clk.date",
                    "            ctx.lineWidth = 2; ctx.strokeStyle = accentColor; ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke()"]
            if it.get("ticks", True):
                out += ["            for (var i = 0; i < 12; i++) { var a = i * Math.PI / 6; ctx.beginPath(); ctx.moveTo(cx + Math.sin(a) * r * 0.86, cy - Math.cos(a) * r * 0.86); ctx.lineTo(cx + Math.sin(a) * r * 0.96, cy - Math.cos(a) * r * 0.96); ctx.stroke() }"]
            out += ["            function hand(angle, len, w, col) { ctx.lineWidth = w; ctx.lineCap = \"round\"; ctx.strokeStyle = col; ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + Math.sin(angle) * r * len, cy - Math.cos(angle) * r * len); ctx.stroke() }",
                    "            hand(((d.getHours() % 12) + d.getMinutes() / 60) * Math.PI / 6, 0.5, 4, handColor)",
                    "            hand((d.getMinutes() + d.getSeconds() / 60) * Math.PI / 30, 0.78, 3, handColor)",
                    "            hand(d.getSeconds() * Math.PI / 30, 0.88, 1.5, accentColor)",
                    "        }", "    }"]
        elif t == "image":
            out += ["    Image {", "        " + geo, "        fillMode: Image.PreserveAspectFit", "        smooth: true",
                    "        source: %s" % qs("file://" + it.get("path", "")), "    }"]
        out.append("")
    out.append("}")
    return "\n".join(out) + "\n"


def doc_paths(name):
    """(json, qml). Each panel lives in its own folder, created *before* the shell first loads from it: Qt caches a
    folder's file list on first access, so a file added later to an already-seen folder fails with
    "File name case mismatch"."""
    return USER_DIR + "/%s.panel.json" % name, USER_DIR + "/%s/main.qml" % name


def trash(path):
    """Soft delete: move a panel file/folder to user/.trash/ (hidden from every list, never overwritten)."""
    import time
    os.makedirs(USER_DIR + "/.trash", exist_ok=True)
    dest = "%s/.trash/%s-%d" % (USER_DIR, os.path.basename(path), time.time())
    os.replace(path, dest)
    return dest


def list_docs():
    os.makedirs(USER_DIR, exist_ok=True)
    return sorted(f[:-len(".panel.json")] for f in os.listdir(USER_DIR) if f.endswith(".panel.json"))


# ---------------------------------------------------------------- the editor widget
def theme_hex(role):
    try:
        p = json.load(open(THEME_JSON))
    except (OSError, ValueError):
        p = {}
    m = {"accent": p.get("primary", "7dff4f"), "strong": p.get("strong", "a6ff7a"), "soft": p.get("soft", "52b82f")}
    if role in m:
        return m[role]
    return ROLES.get(role, (None, "f4f8fc"))[1] or "f4f8fc"


def rgb(c, role_fallback="f4f8fc"):
    c = str(c)
    h = theme_hex(c) if c in ROLES else c.lstrip("#")
    try:
        return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    except ValueError:
        return tuple(int(role_fallback[i:i + 2], 16) / 255 for i in (0, 2, 4))


HANDLES = [(0, 0), (.5, 0), (1, 0), (1, .5), (1, 1), (.5, 1), (0, 1), (0, .5)]  # nw n ne e se s sw w


class CanvasPage(Gtk.Box):

    def __init__(self, studio):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin_top=14, margin_bottom=10,
                         margin_start=16, margin_end=16)
        self.studio = studio
        self.doc = None
        self.sel = None
        self.zoom = 1.0
        self.snap = True
        self.grid = 8
        self.show_grid = True
        self.drag = None
        self.guides = []  # [('v', x) | ('h', y)] shown while dragging
        self.undo_stack, self.redo_stack = [], []
        self.last_key, self.last_t = None, 0.0
        self.pending = None  # snapshot taken at drag start, pushed on the first real movement
        self.save_timer = None
        self.cache = {}  # command -> last stdout, for script/bar previews
        self.building = False

        top = Gtk.Box(spacing=8)
        top.append(Gtk.Label(label="Canvas", xalign=0, css_classes=["title-main"]))
        self.tg_left = Gtk.ToggleButton(label="◧", tooltip_text="Show / hide the toolbox and layers", active=True, css_classes=["mini"])
        self.tg_right = Gtk.ToggleButton(label="◨", tooltip_text="Show / hide the properties", active=True, css_classes=["mini"])
        top.append(self.tg_left)
        self.names = Gtk.StringList()
        self.picker = Gtk.DropDown(model=self.names)
        self.picker.connect("notify::selected", lambda *_: self.on_pick())
        top.append(self.picker)
        self.new_name = Gtk.Entry(placeholder_text="new panel name", width_chars=16)
        top.append(self.new_name)
        nb = Gtk.Button(label="New", css_classes=["mini"])
        nb.connect("clicked", self.on_new)
        top.append(nb)
        self.del_btn = Gtk.Button(label="Delete", css_classes=["mini"])
        self.del_btn.connect("clicked", self.on_delete)
        top.append(self.del_btn)
        top.append(Gtk.Box(hexpand=True))
        top.append(self.tg_right)
        for label, tip, fn in (("↶", "Undo (Ctrl+Z)", lambda *_: self.undo()), ("↷", "Redo (Ctrl+Shift+Z)", lambda *_: self.redo())):
            ub = Gtk.Button(label=label, tooltip_text=tip, css_classes=["mini"])
            ub.connect("clicked", fn)
            top.append(ub)
        top.append(Gtk.Label(label="Grid"))
        gsw = Gtk.Switch(active=True, valign=Gtk.Align.CENTER)
        gsw.connect("notify::active", lambda s, _p: (setattr(self, "show_grid", s.get_active()), self.area.queue_draw()))
        top.append(gsw)
        gsp = Gtk.SpinButton.new_with_range(2, 64, 2)
        gsp.set_value(8)
        gsp.connect("value-changed", lambda s: (setattr(self, "grid", int(s.get_value())), self.area.queue_draw()))
        top.append(gsp)
        top.append(Gtk.Label(label="Snap"))
        sn = Gtk.Switch(active=True, valign=Gtk.Align.CENTER)
        sn.connect("notify::active", lambda s, _p: setattr(self, "snap", s.get_active()))
        top.append(sn)
        top.append(Gtk.Label(label="Zoom"))
        zs = Gtk.SpinButton.new_with_range(0.5, 3, 0.25)
        zs.set_value(1.0)
        zs.set_digits(2)
        zs.connect("value-changed", lambda s: self.set_zoom(s.get_value()))
        top.append(zs)
        self.append(top)
        self.info = Gtk.Label(label="", xalign=0, css_classes=["dim-label"])
        self.append(self.info)

        body = Gtk.Box(spacing=12, vexpand=True)
        self.append(body)

        # toolbox + layer list
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, css_classes=["zone"])
        left.set_size_request(190, -1)
        left.append(Gtk.Label(label="ADD", xalign=0, css_classes=["zone-title"]))
        grid = Gtk.FlowBox(max_children_per_line=2, selection_mode=Gtk.SelectionMode.NONE, column_spacing=4, row_spacing=4)
        for t in DEFAULT_ITEMS:
            b = Gtk.Button(label="%s %s" % (ITEM_ICONS[t], t), css_classes=["mini"])
            b.connect("clicked", lambda _b, t=t: self.add_item(t))
            grid.append(b)
        left.append(grid)
        left.append(Gtk.Label(label="LAYERS", xalign=0, css_classes=["zone-title"], margin_top=8))
        self.layer_list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        left.append(Gtk.ScrolledWindow(child=self.layer_list, vexpand=True))
        lb = Gtk.Box(spacing=4)
        for label, tip, fn in (("▲", "Bring forward", lambda *_: self.reorder(1)), ("▼", "Send back", lambda *_: self.reorder(-1)),
                               ("⧉", "Duplicate (Ctrl+D)", lambda *_: self.duplicate()), ("󰆴", "Delete (Del)", lambda *_: self.delete_item())):
            b = Gtk.Button(label=label, tooltip_text=tip, css_classes=["mini"])
            b.connect("clicked", fn)
            lb.append(b)
        left.append(lb)
        left_rev = Gtk.Revealer(child=left, reveal_child=True, transition_type=Gtk.RevealerTransitionType.SLIDE_RIGHT)
        self.tg_left.connect("toggled", lambda b: left_rev.set_reveal_child(b.get_active()))
        body.append(left_rev)

        # canvas
        self.area = Gtk.DrawingArea(focusable=True, can_focus=True)
        self.area.set_draw_func(self.draw)
        gd = Gtk.GestureDrag()
        gd.connect("drag-begin", self.on_begin)
        gd.connect("drag-update", self.on_update)
        gd.connect("drag-end", self.on_end)
        self.area.add_controller(gd)
        mc = Gtk.EventControllerMotion()
        mc.connect("motion", self.on_motion)
        self.area.add_controller(mc)
        kc = Gtk.EventControllerKey()
        kc.connect("key-pressed", self.on_key)
        self.area.add_controller(kc)
        sw = Gtk.ScrolledWindow(child=self.area, hexpand=True, vexpand=True, css_classes=["editor-wrap"])
        body.append(sw)

        # properties
        self.props = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, css_classes=["zone"])
        self.props.set_size_request(330, -1)
        # hexpand=False: the entries inside the props are hexpand and would otherwise split the width 50/50 with the canvas
        props_rev = Gtk.Revealer(reveal_child=True, transition_type=Gtk.RevealerTransitionType.SLIDE_LEFT, child=Gtk.ScrolledWindow(
            child=self.props, hscrollbar_policy=Gtk.PolicyType.NEVER, hexpand=False, min_content_width=330, max_content_width=420,
            propagate_natural_width=True))
        self.tg_right.connect("toggled", lambda b: props_rev.set_reveal_child(b.get_active()))
        body.append(props_rev)

        self.refresh_names()

    # -------- documents
    def refresh_names(self, select=None):
        self.building = True
        names = list_docs()
        self.names.splice(0, self.names.get_n_items(), names)
        if names:
            self.picker.set_selected(names.index(select) if select in names else 0)
        self.building = False
        self.on_pick()

    def on_pick(self):
        if self.building:
            return
        names = list_docs()
        if not names:
            self.doc = None
            self.info.set_text("No canvas panels yet: type a name and press New.")
            self.rebuild_all()
            return
        name = names[self.picker.get_selected()]
        try:
            self.doc = json.load(open(doc_paths(name)[0]))
        except (OSError, ValueError):
            self.doc = new_doc(name)
        self.sel = None
        self.undo_stack.clear()
        self.redo_stack.clear()
        qml = doc_paths(name)[1]
        edited = False
        try:
            edited = bool(self.doc.get("generated_hash")) and hashlib.md5(open(qml).read().encode()).hexdigest() != self.doc["generated_hash"]
        except OSError:
            pass
        self.info.set_text(("⚠ %s/main.qml was edited in the Code page; saving here regenerates it and overwrites those edits." % name) if edited
                           else "Drag items to move, drag the handles to resize, arrows nudge (Shift = 10px). Saves apply live to the real panel.  Also, my friend Lorfo informed me that BANANAS ARE YELLOW.")
        self.rebuild_all()

    def on_new(self, *_):
        name = "".join(c for c in self.new_name.get_text().strip() if c.isalnum() or c in "-_") or "panel"
        if name in list_docs():
            self.refresh_names(name)
            return
        self.doc = new_doc(name)
        self.save_now()
        self.new_name.set_text("")
        self.refresh_names(name)

    def on_delete(self, *_):
        if not self.doc:
            return
        js, qml = doc_paths(self.doc["name"])
        for p in (js, os.path.dirname(qml)):
            if os.path.exists(p):
                trash(p)
        self.studio.unregister_panel("%s/main.qml" % self.doc["name"])
        self.refresh_names()

    # -------- persistence (debounced, live)
    def touch(self):
        self.area.queue_draw()
        if self.save_timer:
            GLib.source_remove(self.save_timer)
        self.save_timer = GLib.timeout_add(350, self.save_now)

    def save_now(self):
        self.save_timer = None
        if not self.doc:
            return False
        os.makedirs(USER_DIR, exist_ok=True)
        js, qml = doc_paths(self.doc["name"])
        text = gen_qml(self.doc)
        self.doc["generated_hash"] = hashlib.md5(text.encode()).hexdigest()
        os.makedirs(os.path.dirname(qml), exist_ok=True)
        open(qml, "w").write(text)
        json.dump(self.doc, open(js, "w"), indent=2)
        self.studio.register_panel("%s/main.qml" % self.doc["name"])
        self.studio.toast("Canvas saved: panel %s reloaded live." % self.doc["name"])
        return False

    # -------- drawing
    def metrics(self):
        pad = 60
        return pad, pad, self.zoom

    def set_zoom(self, z):
        self.zoom = z
        self.update_size()
        self.area.queue_draw()

    def update_size(self):
        if self.doc:
            pad, _, z = self.metrics()
            self.area.set_content_width(int(self.doc["width"] * z + pad * 2))
            self.area.set_content_height(int(self.doc["height"] * z + pad * 2))

    def draw(self, area, cr, w, h):
        cr.set_source_rgb(0.03, 0.06, 0.09)
        cr.paint()
        if not self.doc:
            return
        pad, _, z = self.metrics()
        d = self.doc
        # dotted grid
        g = self.grid * 2 * z
        cr.set_source_rgba(1, 1, 1, 0.05)
        x = 0.0
        while x < w:
            y = 0.0
            while y < h:
                cr.rectangle(x, y, 1.2, 1.2)
                y += g
            x += g
        cr.fill()
        # card
        W, H = d["width"] * z, d["height"] * z
        ar, ag, ab = rgb("accent")
        if d.get("card", True):
            self.round_rect(cr, pad, pad, W, H, d.get("card_radius", 22) * z)
            br, bg_, bb = rgb("panel")
            cr.set_source_rgba(br, bg_, bb, d.get("card_opacity", 0.78))
            cr.fill_preserve() if d.get("card_border", True) else cr.fill()
            if d.get("card_border", True):
                cr.set_source_rgba(ar, ag, ab, 0.55)
                cr.set_line_width(1)
                cr.stroke()
        else:
            cr.set_source_rgba(1, 1, 1, 0.12)
            cr.set_dash([4, 4])
            cr.rectangle(pad, pad, W, H)
            cr.stroke()
            cr.set_dash([])
        if self.show_grid:
            cr.save()
            self.round_rect(cr, pad, pad, W, H, d.get("card_radius", 22) * z) if d.get("card", True) else cr.rectangle(pad, pad, W, H)
            cr.clip()
            step = self.grid * z
            n = 0
            gx = 0.0
            while gx <= W:
                major = n % 4 == 0
                cr.set_source_rgba(ar, ag, ab, 0.16 if major else 0.06)
                cr.set_line_width(1)
                cr.move_to(pad + round(gx) + 0.5, pad)
                cr.line_to(pad + round(gx) + 0.5, pad + H)
                cr.stroke()
                gx += step
                n += 1
            n = 0
            gy = 0.0
            while gy <= H:
                major = n % 4 == 0
                cr.set_source_rgba(ar, ag, ab, 0.16 if major else 0.06)
                cr.set_line_width(1)
                cr.move_to(pad, pad + round(gy) + 0.5)
                cr.line_to(pad + W, pad + round(gy) + 0.5)
                cr.stroke()
                gy += step
                n += 1
            cr.restore()
        for it in d["items"]:
            self.draw_item(cr, it, pad, z)
        # panel resize handles (outside the item handles' colour so they read as "the canvas")
        for hx, hy in HANDLES:
            cr.new_path()  # draw_item can leave a dangling current point -> stray line to the first handle
            cr.arc(pad + hx * W, pad + hy * H, 5, 0, 2 * math.pi)
            cr.set_source_rgb(0.02, 0.04, 0.06)
            cr.fill_preserve()
            cr.set_source_rgba(1, 0.85, 0.3, 1)
            cr.set_line_width(1.5)
            cr.stroke()
        for kind, v in self.guides:
            cr.set_source_rgba(1, 0.3, 0.8, 0.9)
            cr.set_line_width(1)
            cr.set_dash([4, 3])
            if kind == "v":
                cr.move_to(pad + v * z, pad - 12)
                cr.line_to(pad + v * z, pad + H + 12)
            else:
                cr.move_to(pad - 12, pad + v * z)
                cr.line_to(pad + W + 12, pad + v * z)
            cr.stroke()
            cr.set_dash([])
        if self.sel is not None and self.sel < len(d["items"]):
            it = d["items"][self.sel]
            x, y, iw, ih = pad + it["x"] * z, pad + it["y"] * z, it["w"] * z, it["h"] * z
            cr.set_source_rgba(ar, ag, ab, 0.95)
            cr.set_dash([5, 3])
            cr.set_line_width(1.2)
            cr.rectangle(x, y, iw, ih)
            cr.stroke()
            cr.set_dash([])
            for hx, hy in HANDLES:
                cr.rectangle(x + hx * iw - 4, y + hy * ih - 4, 8, 8)
                cr.set_source_rgb(0.02, 0.04, 0.06)
                cr.fill_preserve()
                cr.set_source_rgba(ar, ag, ab, 1)
                cr.stroke()

    @staticmethod
    def round_rect(cr, x, y, w, h, r):
        r = max(0, min(r, w / 2, h / 2))
        cr.new_sub_path()
        cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
        cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
        cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
        cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
        cr.close_path()

    def preview_text(self, it):
        t = it["type"]
        if t == "text":
            return it.get("text", "")
        if t == "clock":
            import datetime
            return self.qt_format(datetime.datetime.now(), it.get("format", "HH:mm"))
        if t == "script":
            cmd = it.get("command", "")
            self.fetch(cmd)
            return it.get("prefix", "") + self.cache.get(cmd, "…") + it.get("suffix", "")
        return it.get("text", "")

    @staticmethod
    def qt_format(dt, fmt):
        import re
        m = {"dddd": "%A", "ddd": "%a", "dd": "%d", "d": str(dt.day), "MMMM": "%B", "MMM": "%b", "yyyy": "%Y",
             "HH": "%H", "mm": "%M", "ss": "%S"}
        # single pass so the output of one token is never re-matched by another
        fmt = re.sub(r"dddd|ddd|dd|d|MMMM|MMM|yyyy|HH|mm|ss", lambda x: m[x.group(0)], fmt)
        try:
            return dt.strftime(fmt)
        except ValueError:
            return fmt

    def fetch(self, cmd):
        if not cmd or cmd in self.cache:
            return
        self.cache[cmd] = "…"

        def run():
            try:
                out = subprocess.run(["sh", "-c", cmd], capture_output=True, text=True, timeout=4).stdout.strip()
            except Exception:
                out = "?"
            self.cache[cmd] = out
            GLib.idle_add(self.area.queue_draw)

        threading.Thread(target=run, daemon=True).start()

    def draw_item(self, cr, it, pad, z):
        cr.new_path()  # text drawing leaves a current point that the next arc would connect to
        x, y, w, h = pad + it["x"] * z, pad + it["y"] * z, it["w"] * z, it["h"] * z
        t = it["type"]
        if t in ("text", "clock", "script"):
            cr.save()
            cr.rectangle(x, y, w, h)
            cr.clip()
            layout = PangoCairo.create_layout(cr)
            fd = Pango.FontDescription(FONT)
            fd.set_absolute_size(it.get("size", 16) * z * Pango.SCALE)
            fd.set_weight(Pango.Weight(int(it.get("weight", "700"))))
            layout.set_font_description(fd)
            layout.set_text(self.preview_text(it), -1)
            layout.set_width(int(w * Pango.SCALE))
            layout.set_ellipsize(Pango.EllipsizeMode.END)
            layout.set_alignment({"left": Pango.Alignment.LEFT, "center": Pango.Alignment.CENTER, "right": Pango.Alignment.RIGHT}[it.get("align", "left")])
            _, lh = layout.get_pixel_size()
            cr.set_source_rgb(*rgb(it.get("color", "text")))
            cr.move_to(x, y + (h - lh) / 2)
            PangoCairo.show_layout(cr, layout)
            cr.restore()
        elif t == "rect":
            self.round_rect(cr, x, y, w, h, it.get("radius", 0) * z)
            r, g, b = rgb(it.get("color", "accent"))
            cr.set_source_rgba(r, g, b, it.get("opacity", 0.16))
            cr.fill_preserve()
            if it.get("border", 0):
                r, g, b = rgb(it.get("bcolor", "accent"))
                cr.set_source_rgb(r, g, b)
                cr.set_line_width(it["border"] * z)
                cr.stroke()
            else:
                cr.new_path()
        elif t == "bar":
            cmd = it.get("command", "")
            self.fetch(cmd)
            try:
                v = max(0, min(100, float(self.cache.get(cmd, "0")))) / 100
            except ValueError:
                v = 0
            self.round_rect(cr, x, y, w, h, it.get("radius", 5) * z)
            r, g, b = rgb(it.get("track", "muted"))
            cr.set_source_rgba(r, g, b, 0.35)
            cr.fill()
            if v > 0:
                self.round_rect(cr, x, y, max(w * v, 1), h, it.get("radius", 5) * z)
                cr.set_source_rgb(*rgb(it.get("color", "accent")))
                cr.fill()
        elif t == "button":
            self.round_rect(cr, x, y, w, h, it.get("radius", 10) * z)
            r, g, b = rgb(it.get("bg", "accent"))
            cr.set_source_rgba(r, g, b, 0.18)
            cr.fill_preserve()
            cr.set_source_rgba(r, g, b, 0.7)
            cr.set_line_width(1)
            cr.stroke()
            layout = PangoCairo.create_layout(cr)
            fd = Pango.FontDescription(FONT)
            fd.set_absolute_size(it.get("size", 14) * z * Pango.SCALE)
            fd.set_weight(Pango.Weight.BOLD)
            layout.set_font_description(fd)
            layout.set_text(it.get("text", ""), -1)
            lw, lh = layout.get_pixel_size()
            cr.set_source_rgb(*rgb(it.get("color", "text")))
            cr.move_to(x + (w - lw) / 2, y + (h - lh) / 2)
            PangoCairo.show_layout(cr, layout)
        elif t == "line":
            self.round_rect(cr, x, y, w, h, min(w, h) / 2)
            r, g, b = rgb(it.get("color", "accent"))
            cr.set_source_rgba(r, g, b, it.get("opacity", 0.6))
            cr.fill()
        elif t == "circle":
            cr.save()
            cr.translate(x + w / 2, y + h / 2)
            cr.scale(max(w, 1) / 2, max(h, 1) / 2)
            cr.arc(0, 0, 1, 0, 2 * math.pi)
            cr.restore()
            r, g, b = rgb(it.get("color", "accent"))
            cr.set_source_rgba(r, g, b, it.get("opacity", 0.18))
            cr.fill_preserve()
            if it.get("border", 0):
                r, g, b = rgb(it.get("bcolor", "accent"))
                cr.set_source_rgb(r, g, b)
                cr.set_line_width(it["border"] * z)
                cr.stroke()
            else:
                cr.new_path()
        elif t == "icon":
            layout = PangoCairo.create_layout(cr)
            fd = Pango.FontDescription(FONT)
            fd.set_absolute_size(it.get("size", 32) * z * Pango.SCALE)
            layout.set_font_description(fd)
            layout.set_text(it.get("text", ""), -1)
            lw, lh = layout.get_pixel_size()
            cr.set_source_rgb(*rgb(it.get("color", "accent")))
            cr.move_to(x + (w - lw) / 2, y + (h - lh) / 2)
            PangoCairo.show_layout(cr, layout)
        elif t in ("gauge", "bar_ring"):
            cmd = it.get("command", "")
            self.fetch(cmd)
            try:
                v = max(0, min(100, float(self.cache.get(cmd, "0"))))
            except ValueError:
                v = 0
            lw = it.get("thickness", 8) * z
            rad = min(w, h) / 2 - lw / 2 - 1
            cx, cy = x + w / 2, y + h / 2
            cr.set_line_cap(1)
            cr.set_line_width(lw)
            tr, tg, tb = rgb(it.get("track", "muted"))
            cr.set_source_rgba(tr, tg, tb, 0.35)
            cr.arc(cx, cy, rad, 0, 2 * math.pi)
            cr.stroke()
            cr.set_source_rgb(*rgb(it.get("color", "accent")))
            cr.arc(cx, cy, rad, -math.pi / 2, -math.pi / 2 + 2 * math.pi * v / 100)
            cr.stroke()
            layout = PangoCairo.create_layout(cr)
            fd = Pango.FontDescription(FONT)
            fd.set_absolute_size(it.get("size", 18) * z * Pango.SCALE)
            fd.set_weight(Pango.Weight.HEAVY)
            layout.set_font_description(fd)
            layout.set_text("%d%s" % (round(v), it.get("suffix", "")), -1)
            lw2, lh = layout.get_pixel_size()
            cr.set_source_rgb(*rgb("text"))
            cr.move_to(cx - lw2 / 2, cy - lh / 2)
            PangoCairo.show_layout(cr, layout)
        elif t == "graph":
            n = max(10, it.get("points", 60))
            pts = [0.5 + 0.35 * math.sin(i / 4.0) * math.cos(i / 9.0) for i in range(n)]
            cr.save()
            cr.rectangle(x, y, w, h)
            cr.clip()
            cr.move_to(x, y + h)
            cr.new_path()
            for i, p in enumerate(pts):
                px, py = x + w * i / (n - 1), y + h - p * (h - 2) - 1
                (cr.move_to if i == 0 else cr.line_to)(px, py)
            r, g, b = rgb(it.get("color", "accent"))
            cr.set_source_rgb(r, g, b)
            cr.set_line_width(2 * z)
            cr.stroke_preserve()
            cr.line_to(x + w, y + h)
            cr.line_to(x, y + h)
            cr.close_path()
            cr.set_source_rgba(r, g, b, it.get("fill", 0.18))
            cr.fill()
            cr.restore()
        elif t == "slider":
            self.round_rect(cr, x, y, w, h, h / 2)
            r, g, b = rgb(it.get("track", "muted"))
            cr.set_source_rgba(r, g, b, 0.3)
            cr.fill()
            self.round_rect(cr, x, y, max(h, w * 0.6), h, h / 2)
            cr.set_source_rgb(*rgb(it.get("color", "accent")))
            cr.fill()
        elif t == "output":
            cmd = it.get("command", "")
            self.fetch(cmd)
            cr.save()
            cr.rectangle(x, y, w, h)
            cr.clip()
            layout = PangoCairo.create_layout(cr)
            fd = Pango.FontDescription(FONT)
            fd.set_absolute_size(it.get("size", 13) * z * Pango.SCALE)
            layout.set_font_description(fd)
            layout.set_text(self.cache.get(cmd, "…"), -1)
            if it.get("wrap", True):
                layout.set_width(int(w * Pango.SCALE))
                layout.set_wrap(Pango.WrapMode.WORD_CHAR)
            cr.set_source_rgb(*rgb(it.get("color", "secondary")))
            cr.move_to(x, y)
            PangoCairo.show_layout(cr, layout)
            cr.restore()
        elif t == "analogclock":
            import datetime
            now = datetime.datetime.now()
            rad = min(w, h) / 2 - 3
            cx, cy = x + w / 2, y + h / 2
            ar, ag, ab = rgb(it.get("color", "accent"))
            cr.set_source_rgb(ar, ag, ab)
            cr.set_line_width(2)
            cr.arc(cx, cy, rad, 0, 2 * math.pi)
            cr.stroke()
            if it.get("ticks", True):
                for i in range(12):
                    a = i * math.pi / 6
                    cr.move_to(cx + math.sin(a) * rad * 0.86, cy - math.cos(a) * rad * 0.86)
                    cr.line_to(cx + math.sin(a) * rad * 0.96, cy - math.cos(a) * rad * 0.96)
                cr.stroke()
            cr.set_line_cap(1)
            for ang, ln, wd, col in (((now.hour % 12 + now.minute / 60) * math.pi / 6, 0.5, 4, it.get("hands", "text")),
                                     ((now.minute + now.second / 60) * math.pi / 30, 0.78, 3, it.get("hands", "text")),
                                     (now.second * math.pi / 30, 0.88, 1.5, it.get("color", "accent"))):
                cr.set_source_rgb(*rgb(col))
                cr.set_line_width(wd)
                cr.move_to(cx, cy)
                cr.line_to(cx + math.sin(ang) * rad * ln, cy - math.cos(ang) * rad * ln)
                cr.stroke()
        elif t == "image":
            cr.set_source_rgba(1, 1, 1, 0.08)
            cr.rectangle(x, y, w, h)
            cr.fill()
            layout = PangoCairo.create_layout(cr)
            layout.set_font_description(Pango.FontDescription("%s 12" % FONT))
            layout.set_text("󰋩  " + os.path.basename(it.get("path", "")) , -1)
            cr.set_source_rgba(1, 1, 1, 0.5)
            cr.move_to(x + 6, y + 6)
            PangoCairo.show_layout(cr, layout)

    # -------- interaction
    def hit(self, px, py):
        pad, _, z = self.metrics()
        if self.sel is not None and self.doc and self.sel < len(self.doc["items"]):
            it = self.doc["items"][self.sel]
            x, y, w, h = pad + it["x"] * z, pad + it["y"] * z, it["w"] * z, it["h"] * z
            for i, (hx, hy) in enumerate(HANDLES):
                if abs(px - (x + hx * w)) <= 7 and abs(py - (y + hy * h)) <= 7:
                    return ("handle", self.sel, i)
        W, H = self.doc["width"] * z, self.doc["height"] * z
        for i, (hx, hy) in enumerate(HANDLES):
            if abs(px - (pad + hx * W)) <= 8 and abs(py - (pad + hy * H)) <= 8:
                return ("panel", None, i)
        for i in range(len(self.doc["items"]) - 1, -1, -1):
            it = self.doc["items"][i]
            x, y, w, h = pad + it["x"] * z, pad + it["y"] * z, it["w"] * z, it["h"] * z
            if x <= px <= x + w and y <= py <= y + h:
                return ("item", i, None)
        return (None, None, None)

    def on_begin(self, g, x, y):
        self.area.grab_focus()
        if not self.doc:
            return
        kind, i, hnd = self.hit(x, y)
        self.pending = self.snapshot() if kind in ("panel", "item", "handle") else None
        if kind == "panel":
            self.drag = dict(kind="panel", handle=hnd, w0=self.doc["width"], h0=self.doc["height"],
                             pos=[(it["x"], it["y"]) for it in self.doc["items"]])
            return
        if kind is None:
            self.sel = None
            self.drag = None
        else:
            self.sel = i
            it = self.doc["items"][i]
            self.drag = dict(kind=kind, handle=hnd, i=i, x=it["x"], y=it["y"], w=it["w"], h=it["h"])
        self.rebuild_props()
        self.rebuild_layers()
        self.area.queue_draw()

    def snapv(self, v):
        return round(v / self.grid) * self.grid if self.snap else round(v)

    def snap_axis(self, pos, size, axis, skip):
        """Snap an item edge/centre to the panel's edges/centre or to other items' edges/centres (magnetic guides)."""
        total = self.doc["width" if axis == "x" else "height"]
        targets = [0, total / 2, total]
        key, sk = ("x", "w") if axis == "x" else ("y", "h")
        for i, o in enumerate(self.doc["items"]):
            if i != skip:
                targets += [o[key], o[key] + o[sk] / 2, o[key] + o[sk]]
        thr = 6 / self.zoom
        best = None
        for own in (pos, pos + size / 2, pos + size):
            for tg in targets:
                dlt = tg - own
                if abs(dlt) <= thr and (best is None or abs(dlt) < abs(best[0])):
                    best = (dlt, tg)
        return (pos + best[0], best[1]) if best else (pos, None)

    def on_update(self, g, dx, dy):
        d = self.drag
        if not d or not self.doc:
            return
        z = self.zoom
        it = self.doc["items"][d["i"]] if "i" in d else None
        dx, dy = dx / z, dy / z
        if self.pending and (abs(dx) >= 1 or abs(dy) >= 1):
            self.checkpoint(snap=self.pending)
            self.pending = None
        if d["kind"] == "panel":
            hx, hy = HANDLES[d["handle"]]
            doc = self.doc
            nw, nh = d["w0"], d["h0"]
            if hx == 1:
                nw = max(40, self.snapv(d["w0"] + dx))
            elif hx == 0:
                nw = max(40, self.snapv(d["w0"] - dx))
            if hy == 1:
                nh = max(24, self.snapv(d["h0"] + dy))
            elif hy == 0:
                nh = max(24, self.snapv(d["h0"] - dy))
            sx = nw - d["w0"] if hx == 0 else 0   # dragging the left/top edge: items keep their place on the panel's new origin
            sy = nh - d["h0"] if hy == 0 else 0
            doc["width"], doc["height"] = nw, nh
            for it, (ox, oy) in zip(doc["items"], d["pos"]):
                it["x"], it["y"] = ox + sx, oy + sy
            self.update_size()
            self.sync_geometry()
            self.sync_panel_spins()
        elif d["kind"] == "item":
            nx, gx = self.snap_axis(self.snapv(d["x"] + dx), it["w"], "x", d["i"])
            ny, gy = self.snap_axis(self.snapv(d["y"] + dy), it["h"], "y", d["i"])
            it["x"], it["y"] = round(nx), round(ny)
            self.guides = ([("v", gx)] if gx is not None else []) + ([("h", gy)] if gy is not None else [])
        else:
            hx, hy = HANDLES[d["handle"]]
            x0, y0, x1, y1 = d["x"], d["y"], d["x"] + d["w"], d["y"] + d["h"]
            if hx == 0:
                x0 = self.snapv(d["x"] + dx)
            elif hx == 1:
                x1 = self.snapv(d["x"] + d["w"] + dx)
            if hy == 0:
                y0 = self.snapv(d["y"] + dy)
            elif hy == 1:
                y1 = self.snapv(d["y"] + d["h"] + dy)
            x0, x1 = min(x0, x1 - 8), max(x1, x0 + 8)
            y0, y1 = min(y0, y1 - 8), max(y1, y0 + 8)
            it.update(x=x0, y=y0, w=x1 - x0, h=y1 - y0)
        self.sync_geometry()
        self.area.queue_draw()

    def on_end(self, g, dx, dy):
        self.pending = None
        if self.drag:
            self.drag = None
            self.guides = []
            self.touch()
        self.area.queue_draw()

    def on_key(self, ctrl, keyval, keycode, state):
        name = Gdk.keyval_name(keyval)
        ctrl_on = bool(state & Gdk.ModifierType.CONTROL_MASK)
        if ctrl_on and name in ("z", "Z"):
            (self.redo if state & Gdk.ModifierType.SHIFT_MASK else self.undo)()
            return True
        if ctrl_on and name in ("y", "Y"):
            self.redo()
            return True
        step = 10 if state & Gdk.ModifierType.SHIFT_MASK else (self.grid if self.snap else 1)
        if not self.doc or self.sel is None:
            return False
        it = self.doc["items"][self.sel]
        moved = {"Left": (-step, 0), "Right": (step, 0), "Up": (0, -step), "Down": (0, step)}.get(name)
        if moved:
            self.checkpoint("nudge")
            it["x"] += moved[0]
            it["y"] += moved[1]
            self.sync_geometry()
            self.touch()
            return True
        if name == "Delete":
            self.delete_item()
            return True
        if name in ("d", "D") and state & Gdk.ModifierType.CONTROL_MASK:
            self.duplicate()
            return True
        return False

    # -------- undo / redo (whole-document snapshots)
    def snapshot(self):
        return (json.dumps(self.doc), self.sel)

    def checkpoint(self, key=None, snap=None):
        """Remember the current state before a change. Edits with the same key within 0.8 s (typing, spinner clicks,
        arrow-key nudges) collapse into one undo step."""
        import time
        if not self.doc:
            return
        now = time.monotonic()
        if key is not None and key == self.last_key and now - self.last_t < 0.8:
            self.last_t = now
            return
        self.undo_stack.append(snap or self.snapshot())
        del self.undo_stack[:-200]
        self.redo_stack.clear()
        self.last_key, self.last_t = key, now

    def restore(self, state):
        self.doc = json.loads(state[0])
        self.sel = state[1] if state[1] is not None and state[1] < len(self.doc["items"]) else None
        self.last_key = None
        self.rebuild_all()
        self.touch()

    def undo(self, *_):
        if not self.doc or not self.undo_stack:
            self.studio.toast("Nothing to undo.")
            return
        self.redo_stack.append(self.snapshot())
        self.restore(self.undo_stack.pop())
        self.studio.toast("Undo (%d left)" % len(self.undo_stack))

    def redo(self, *_):
        if not self.doc or not self.redo_stack:
            self.studio.toast("Nothing to redo.")
            return
        self.undo_stack.append(self.snapshot())
        self.restore(self.redo_stack.pop())
        self.studio.toast("Redo (%d left)" % len(self.redo_stack))

    # -------- item operations
    def add_item(self, t):
        if not self.doc:
            return
        self.checkpoint()
        it = dict(type=t, x=self.snapv(self.doc["width"] / 2 - 40), y=self.snapv(self.doc["height"] / 2 - 14), **json.loads(json.dumps(DEFAULT_ITEMS[t])))
        self.doc["items"].append(it)
        self.sel = len(self.doc["items"]) - 1
        self.rebuild_all()
        self.touch()

    def delete_item(self):
        if self.doc and self.sel is not None:
            self.checkpoint()
            self.doc["items"].pop(self.sel)
            self.sel = None
            self.rebuild_all()
            self.touch()

    def duplicate(self):
        if self.doc and self.sel is not None:
            self.checkpoint()
            it = json.loads(json.dumps(self.doc["items"][self.sel]))
            it["x"] += 16
            it["y"] += 16
            self.doc["items"].append(it)
            self.sel = len(self.doc["items"]) - 1
            self.rebuild_all()
            self.touch()

    def reorder(self, d):
        if not self.doc or self.sel is None:
            return
        j = self.sel + d
        its = self.doc["items"]
        if 0 <= j < len(its):
            self.checkpoint()
            its[self.sel], its[j] = its[j], its[self.sel]
            self.sel = j
            self.rebuild_all()
            self.touch()

    # -------- side panels
    def rebuild_all(self):
        self.update_size()
        self.rebuild_layers()
        self.rebuild_props()
        self.area.queue_draw()

    def rebuild_layers(self):
        while (r := self.layer_list.get_first_child()):
            self.layer_list.remove(r)
        if not self.doc:
            return
        for i in range(len(self.doc["items"]) - 1, -1, -1):
            it = self.doc["items"][i]
            name = {"text": it.get("text", ""), "clock": it.get("format", ""), "script": it.get("command", ""),
                    "button": it.get("text", ""), "image": os.path.basename(it.get("path", ""))}.get(it["type"], "")
            b = Gtk.Button(label="%s %s" % (ITEM_ICONS[it["type"]], (name or it["type"])[:22]), has_frame=False,
                           css_classes=["chip"] + (["selected"] if i == self.sel else []), margin_bottom=2)
            b.get_child().set_xalign(0)
            b.connect("clicked", lambda _b, i=i: self.pick_layer(i))
            self.layer_list.append(b)

    def pick_layer(self, i):
        self.sel = i
        self.rebuild_layers()
        self.rebuild_props()
        self.area.queue_draw()

    def sync_panel_spins(self):
        for key, sp in getattr(self, "panel_spins", {}).items():
            self.building = True
            sp.set_value(self.doc[key])
            self.building = False

    def on_motion(self, ctrl, x, y):
        if not self.doc or self.drag:
            return
        kind, _i, hnd = self.hit(x, y)
        names = ["nw-resize", "n-resize", "ne-resize", "e-resize", "se-resize", "s-resize", "sw-resize", "w-resize"]
        name = names[hnd] if kind in ("handle", "panel") else ("move" if kind == "item" else "default")
        self.area.set_cursor(Gdk.Cursor.new_from_name(name))

    def sync_geometry(self):
        """Keep the x/y/w/h spinners in step with a drag, without rebuilding the form."""
        for key, sp in getattr(self, "geo_spins", {}).items():
            it = self.doc["items"][self.sel]
            self.building = True
            sp.set_value(it[key])
            self.building = False

    def rebuild_props(self):
        while (c := self.props.get_first_child()):
            self.props.remove(c)
        self.geo_spins = {}
        if not self.doc:
            return
        d = self.doc
        self.props.append(Gtk.Label(label="PANEL", xalign=0, css_classes=["zone-title"]))
        g = Gtk.Grid(row_spacing=5, column_spacing=8)
        self.props.append(g)

        def spin(r, label, key, lo, hi, step=1, target=d, col=0):
            g.attach(Gtk.Label(label=label, xalign=0), col, r, 1, 1)
            s = Gtk.SpinButton.new_with_range(lo, hi, step)
            s.set_value(target.get(key, 0))
            s.connect("value-changed", lambda w: self.set_val(target, key, w.get_value() if step < 1 else int(w.get_value()), rebuild=key in ("width", "height")))
            g.attach(s, col + 1, r, 1, 1)
            return s

        self.panel_spins = {"width": spin(0, "Width", "width", 40, 3000), "height": spin(0, "Height", "height", 24, 2000, col=2)}
        g.attach(Gtk.Label(label="Position", xalign=0), 0, 1, 1, 1)
        pos = Gtk.DropDown.new_from_strings(POSITIONS)
        pos.set_selected(POSITIONS.index(d.get("position", "bottom-right")))
        pos.connect("notify::selected", lambda w, _p: self.set_val(d, "position", POSITIONS[w.get_selected()]))
        g.attach(pos, 1, 1, 1, 1)
        g.attach(Gtk.Label(label="Layer", xalign=0), 2, 1, 1, 1)
        lay = Gtk.DropDown.new_from_strings(LAYERS)
        lay.set_selected(LAYERS.index(d.get("layer", "bottom")))
        lay.connect("notify::selected", lambda w, _p: self.set_val(d, "layer", LAYERS[w.get_selected()]))
        g.attach(lay, 3, 1, 1, 1)
        spin(2, "Margin X", "margin_x", 0, 3000)
        spin(2, "Margin Y", "margin_y", 0, 3000, col=2)
        mons = monitor_names() or [d.get("monitor", "")]
        if d.get("monitor") and d["monitor"] not in mons:
            mons.append(d["monitor"])
        g.attach(Gtk.Label(label="Monitor", xalign=0), 0, 5, 1, 1)
        md = Gtk.DropDown.new_from_strings(mons)
        md.set_selected(mons.index(d.get("monitor")) if d.get("monitor") in mons else 0)
        md.connect("notify::selected", lambda w, _p: self.set_val(d, "monitor", mons[w.get_selected()]))
        g.attach(md, 1, 5, 1, 1)
        g.attach(Gtk.Label(label="Card", xalign=0), 0, 3, 1, 1)
        sw = Gtk.Switch(active=d.get("card", True), halign=Gtk.Align.START, valign=Gtk.Align.CENTER)
        sw.connect("notify::active", lambda w, _p: self.set_val(d, "card", w.get_active()))
        g.attach(sw, 1, 3, 1, 1)
        g.attach(Gtk.Label(label="Border", xalign=0), 2, 3, 1, 1)
        bsw = Gtk.Switch(active=d.get("card_border", True), halign=Gtk.Align.START, valign=Gtk.Align.CENTER)
        bsw.connect("notify::active", lambda w, _p: self.set_val(d, "card_border", w.get_active()))
        g.attach(bsw, 3, 3, 1, 1)
        spin(4, "Radius", "card_radius", 0, 120)
        spin(4, "Opacity", "card_opacity", 0, 1, 0.05, col=2).set_digits(2)

        if self.sel is None or self.sel >= len(d["items"]):
            self.props.append(Gtk.Label(label="Click an item on the canvas to edit it, or add one from the toolbox.",
                                        xalign=0, wrap=True, css_classes=["dim-label"], margin_top=10))
            return
        it = d["items"][self.sel]
        self.props.append(Gtk.Label(label="%s %s" % (ITEM_ICONS[it["type"]], it["type"].upper()), xalign=0,
                                    css_classes=["zone-title"], margin_top=10))
        gg = Gtk.Grid(row_spacing=5, column_spacing=8)
        self.props.append(gg)
        for n, (key, label, lo, hi) in enumerate((("x", "X", -500, 4000), ("y", "Y", -500, 4000), ("w", "W", 8, 4000), ("h", "H", 8, 4000))):
            r, c = divmod(n, 2)
            gg.attach(Gtk.Label(label=label, xalign=0), c * 2, r, 1, 1)
            s = Gtk.SpinButton.new_with_range(lo, hi, 1)
            s.set_value(it[key])
            s.connect("value-changed", lambda w, key=key: None if self.building else self.set_val(it, key, int(w.get_value())))
            gg.attach(s, c * 2 + 1, r, 1, 1)
            self.geo_spins[key] = s
        ab = Gtk.Box(spacing=4, margin_top=4)
        ab.append(Gtk.Label(label="Align to panel", css_classes=["dim-label"], margin_end=4))
        for label, tip, fn in (("⇤", "Align left", lambda it: it.update(x=0)),
                               ("↔", "Center horizontally", lambda it: it.update(x=round((d["width"] - it["w"]) / 2))),
                               ("⇥", "Align right", lambda it: it.update(x=d["width"] - it["w"])),
                               ("⤒", "Align top", lambda it: it.update(y=0)),
                               ("↕", "Center vertically", lambda it: it.update(y=round((d["height"] - it["h"]) / 2))),
                               ("⤓", "Align bottom", lambda it: it.update(y=d["height"] - it["h"])),
                               ("◎", "Center both", lambda it: it.update(x=round((d["width"] - it["w"]) / 2), y=round((d["height"] - it["h"]) / 2)))):
            b = Gtk.Button(label=label, tooltip_text=tip, css_classes=["mini"])
            b.connect("clicked", lambda _b, fn=fn: self.align_item(fn))
            ab.append(b)
        self.props.append(ab)
        form = Gtk.Grid(row_spacing=5, column_spacing=8)
        self.props.append(form)
        for r, (key, label, kind, extra) in enumerate(SCHEMA[it["type"]]):
            form.attach(Gtk.Label(label=label, xalign=0, width_chars=14), 0, r, 1, 1)
            if kind == "str":
                e = Gtk.Entry(text=str(it.get(key, "")), hexpand=True)
                e.connect("changed", lambda w, key=key: self.set_val(it, key, w.get_text(), rebuild=key in ("text", "command")))
                form.attach(e, 1, r, 1, 1)
            elif kind in ("int", "float"):
                s = Gtk.SpinButton.new_with_range(extra[0], extra[1], 1 if kind == "int" else 0.05)
                s.set_value(it.get(key, extra[0]))
                if kind == "float":
                    s.set_digits(2)
                s.connect("value-changed", lambda w, key=key, kind=kind: self.set_val(it, key, int(w.get_value()) if kind == "int" else round(w.get_value(), 2)))
                form.attach(s, 1, r, 1, 1)
            elif key == "align":  # the three classic alignment buttons
                box = Gtk.Box(css_classes=["linked"], halign=Gtk.Align.START)
                first = None
                for val, icon in (("left", "format-justify-left-symbolic"), ("center", "format-justify-center-symbolic"),
                                  ("right", "format-justify-right-symbolic")):
                    tb = Gtk.ToggleButton(icon_name=icon, tooltip_text="Align " + val, active=it.get(key, "left") == val)
                    if first is None:
                        first = tb
                    else:
                        tb.set_group(first)
                    tb.connect("toggled", lambda w, val=val: self.set_val(it, key, val) if w.get_active() else None)
                    box.append(tb)
                form.attach(box, 1, r, 1, 1)
            elif kind == "bool":
                sw = Gtk.Switch(active=bool(it.get(key, True)), halign=Gtk.Align.START, valign=Gtk.Align.CENTER)
                sw.connect("notify::active", lambda w, _p, key=key: self.set_val(it, key, w.get_active()))
                form.attach(sw, 1, r, 1, 1)
            elif kind == "glyph":
                row = Gtk.Box(spacing=4)
                e = Gtk.Entry(text=str(it.get(key, "")), width_chars=6)
                e.connect("changed", lambda w, key=key: self.set_val(it, key, w.get_text()))
                row.append(e)
                mb = Gtk.MenuButton(label="Pick…", css_classes=["mini"])
                pop = Gtk.Popover()
                fb = Gtk.FlowBox(max_children_per_line=8, selection_mode=Gtk.SelectionMode.NONE)
                for gch in GLYPHS:
                    gb = Gtk.Button(label=gch, has_frame=False)
                    gb.connect("clicked", lambda _b, gch=gch, e=e, pop=pop: (e.set_text(gch), pop.popdown()))
                    fb.append(gb)
                pop.set_child(fb)
                mb.set_popover(pop)
                row.append(mb)
                form.attach(row, 1, r, 1, 1)
            elif kind == "choice":
                dd = Gtk.DropDown.new_from_strings(extra)
                cur = str(it.get(key, extra[0]))
                dd.set_selected(extra.index(cur) if cur in extra else 0)
                dd.connect("notify::selected", lambda w, _p, key=key, extra=extra: self.set_val(it, key, extra[w.get_selected()]))
                form.attach(dd, 1, r, 1, 1)
            else:  # colour: role dropdown (follows the Hyprland theme) or #hex
                form.attach(self.color_box(it, key), 1, r, 1, 1)

    def align_item(self, fn):
        if not self.doc or self.sel is None:
            return
        self.checkpoint()
        fn(self.doc["items"][self.sel])
        self.sync_geometry()
        self.touch()

    def color_box(self, it, key):
        box = Gtk.Box(spacing=4)
        names = list(ROLES) + ["custom"]
        cur = str(it.get(key, "text"))
        dd = Gtk.DropDown.new_from_strings(names)
        dd.set_selected(names.index(cur) if cur in ROLES else len(names) - 1)
        e = Gtk.Entry(text=cur if cur not in ROLES else "#", width_chars=8, sensitive=cur not in ROLES)

        def on_dd(w, _p):
            n = names[w.get_selected()]
            e.set_sensitive(n == "custom")
            if n != "custom":
                self.set_val(it, key, n)
            else:
                self.set_val(it, key, e.get_text() if e.get_text().startswith("#") and len(e.get_text()) in (4, 7) else "#ffffff")

        dd.connect("notify::selected", on_dd)
        e.connect("changed", lambda w: self.set_val(it, key, w.get_text()) if len(w.get_text()) in (4, 7) and w.get_text().startswith("#") else None)
        box.append(dd)
        box.append(e)
        return box

    def set_val(self, target, key, val, rebuild=False):
        if self.building:
            return
        if target.get(key) == val:
            return
        self.checkpoint((id(target), key))
        target[key] = val
        if rebuild:
            self.cache.pop(val if key == "command" else None, None)
        if key in ("width", "height"):
            self.update_size()
        if key in ("text", "command", "format"):
            self.rebuild_layers()
        self.touch()
