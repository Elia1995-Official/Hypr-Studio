//@ pragma UseQApplication
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.I3._Ipc
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Hyprland
import Quickshell.Widgets

ShellRoot {
    id: shell

    property string timeText: "00:00:00"
    property string dateText: "Thu 07 May"
    property string modeText: ""
    property string volumeText: "--%"
    property bool volumeMuted: false
    property string networkText: "Offline"
    // Workspace state comes from hyprctl: the i3 IPC module has no Hyprland backend.
    property int focusedWorkspaceNumber: 0
    property var wsOccupied: ({})

    // ---- bar layout: ~/.config/quickshell/layout.json (edited by Hypr Studio); falls back to the built-in order
    readonly property var defaultBarLayout: ({
        gap: 10,
        left: [{ type: "workspaces" }, { type: "elsewhere" }, { type: "mode" }],
        center: [{ type: "start" }],
        right: [{ type: "tray" }, { type: "network" }, { type: "visualizer" }, { type: "volume" }, { type: "clock" }],
        panels: []
    })
    property var barLayout: defaultBarLayout

    FileView {
        id: layoutFile
        path: "/home/elia1995/.config/quickshell/layout.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                var j = JSON.parse(text())
                var d = shell.defaultBarLayout
                shell.barLayout = {
                    gap: j.gap !== undefined ? j.gap : d.gap,
                    left: j.left || d.left, center: j.center || d.center, right: j.right || d.right,
                    panels: j.panels || []
                }
            } catch (error) { shell.barLayout = shell.defaultBarLayout }
        }
    }

    // user panels: each is a self-contained QML file in ~/.config/quickshell/user/ (hot reloaded by Quickshell)
    Variants {
        model: shell.barLayout.panels
        QtObject {
            id: host
            required property var modelData
            readonly property string qmlPath: "/home/elia1995/.config/quickshell/user/" + modelData.file
            readonly property bool wanted: modelData.enabled !== false
            property var obj: null
            property bool loaded: false

            // The panel's QML text is read from disk and instantiated here, so saving the file recreates the panel
            // (Quickshell's own reload does not re-read files loaded through a Loader).
            function build() {
                if (obj) { obj.destroy(); obj = null }
                if (!wanted || !loaded) return
                try {
                    obj = Qt.createQmlObject(view.text(), host, "file://" + qmlPath)
                } catch (error) {
                    console.warn("user panel " + modelData.file + ": " + error)
                }
            }
            onWantedChanged: build()

            property var viewer: FileView {
                id: view
                path: host.qmlPath
                watchChanges: true
                printErrors: false
                onFileChanged: reload()
                onLoaded: { host.loaded = true; host.build() }
            }
        }
    }

    // ---- wallpaper crossfade: hold the old image over the desktop while hyprpaper swaps, then fade it out
    property string fadeSource: ""
    property bool fadeActive: false
    property real fadeOpacity: 0
    property bool fadeReady: false

    FileView {
        path: "/home/elia1995/.config/hypr/.wallpaper_fade"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            var old = text().split("\n")[0].trim()
            if (!shell.fadeReady) { shell.fadeReady = true; return }   // ignore the initial load
            if (old === "") return
            shell.fadeSource = "file://" + old
            wallFade.restart()
        }
    }

    SequentialAnimation {
        id: wallFade
        ScriptAction { script: { shell.fadeOpacity = 1; shell.fadeActive = true } }
        PauseAnimation { duration: 1000 }
        NumberAnimation { target: shell; property: "fadeOpacity"; to: 0; duration: 1200; easing.type: Easing.InOutQuad }
        ScriptAction { script: { shell.fadeActive = false; shell.fadeSource = "" } }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: shell.fadeActive
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "wallfade"
            color: "transparent"
            Image {
                anchors.fill: parent
                source: shell.fadeSource
                fillMode: Image.PreserveAspectCrop
                opacity: shell.fadeOpacity
                cache: false
            }
        }
    }
    property var wsVisible: ({})
    readonly property int windowsElsewhere: {
        var n = 0
        for (var id in wsOccupied)
            if (Number(id) !== focusedWorkspaceNumber && id > 0)
                n += wsOccupied[id]
        return n
    }

    function gotoWorkspace(n) {
        wsSwitch.command = ["hyprctl", "dispatch", "hl.dsp.focus({ workspace = " + n + " })"]
        wsSwitch.running = true
        focusedWorkspaceNumber = n
    }

    Process {
        id: wsSwitch
        running: false
        onRunningChanged: if (!running) { wsProbe.running = true; wsMonitors.running = true }
    }

    Process {
        id: wsMonitors
        command: ["hyprctl", "monitors", "-j"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var vis = {}, focus = 0
                    JSON.parse(this.text).forEach(function(m) {
                        vis[m.activeWorkspace.id] = true
                        if (m.focused) focus = m.activeWorkspace.id
                    })
                    shell.wsVisible = vis
                    if (focus > 0) shell.focusedWorkspaceNumber = focus
                } catch (error) {}
            }
        }
    }

    Process {
        id: wsProbe
        command: ["hyprctl", "workspaces", "-j"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var map = {}
                    JSON.parse(this.text).forEach(function(w) { map[w.id] = w.windows })
                    shell.wsOccupied = map
                } catch (error) {}
            }
        }
    }

    Timer {
        interval: 400
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { wsProbe.running = true; wsMonitors.running = true }
    }
    property bool launcherOpen: false
    property string launcherMonitorName: ""
    property string launcherQuery: ""
    property string launcherCategory: "All"
    property bool appsLoading: false
    property bool calendarOpen: false
    property string calendarMonitorName: ""
    property int calendarMonth: new Date().getMonth()
    property int calendarYear: new Date().getFullYear()
    property string calendarSelectedDate: ""
    property string calendarEventTime: ""
    property string calendarEventTitle: ""
    property string calendarEventNote: ""
    property var calendarEvents: []
    property var notifiedEvents: ({})
    property var appList: []
    property bool audioPlaying: false
    property string trackText: "No player"
    property var visualBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property string launcherMode: "apps"
    property int launcherIndex: 0
    property string launcherHint: ""
    readonly property var launcherResults: filteredApps()
    onLauncherQueryChanged: launcherIndex = 0
    onLauncherCategoryChanged: launcherIndex = 0

    function cycleCategory(dir) {
        var c = launcherCategories()
        var i = c.indexOf(launcherCategory)
        launcherCategory = c[(i + dir + c.length) % c.length]
    }
    property string aurQuery: ""
    property var aurResults: []
    property bool aurSearching: false
    property string aurError: ""
    property int aurSearchGeneration: 0
    property string aurDebounceQuery: ""
    property var sidebarShortcuts: []
    property var sidebarActionOrder: ["terminal", "files", "spotify", "vencord", "zen", "audio", "lock"]
    property var sidebarActionOverrides: ({})
    property var sidebarSectionOrder: ["overview", "media", "workspaces", "actions"]

    function run(cmd) {
        commandRunner.command = ["sh", "-c", cmd]
        commandRunner.running = true
    }

    function runMediaCommand(cmd) {
        run(cmd)
        if (cmd.indexOf("play-pause") !== -1)
            audioPlaying = !audioPlaying
        mediaRefreshTimer.restart()
    }

    function updateClock() {
        var now = new Date()
        var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        timeText = String(now.getHours()).padStart(2, "0") + ":" + String(now.getMinutes()).padStart(2, "0") + ":" + String(now.getSeconds()).padStart(2, "0")
        dateText = days[now.getDay()] + " " + String(now.getDate()).padStart(2, "0") + " " + months[now.getMonth()]
    }

    function isoDate(date) {
        return date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0") + "-" + String(date.getDate()).padStart(2, "0")
    }

    function todayIso() {
        return isoDate(new Date())
    }

    function monthName(month) {
        return ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"][month]
    }

    function daysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate()
    }

    function calendarDayDate(day) {
        return calendarYear + "-" + String(calendarMonth + 1).padStart(2, "0") + "-" + String(day).padStart(2, "0")
    }

    function calendarGridDay(index) {
        var first = new Date(calendarYear, calendarMonth, 1).getDay()
        var offset = (first + 6) % 7
        var day = index - offset + 1
        return day >= 1 && day <= daysInMonth(calendarYear, calendarMonth) ? day : 0
    }

    function selectedEvents() {
        var out = []
        for (var i = 0; i < calendarEvents.length; ++i) {
            if (calendarEvents[i].date === calendarSelectedDate)
                out.push(calendarEvents[i])
        }
        out.sort(function(a, b) { return String(a.time || "99:99").localeCompare(String(b.time || "99:99")) })
        return out
    }

    function eventsForDate(date) {
        var count = 0
        for (var i = 0; i < calendarEvents.length; ++i) {
            if (calendarEvents[i].date === date)
                count++
        }
        return count
    }

    function loadCalendarEvents() {
        try {
            var text = calendarFile.text().trim()
            calendarEvents = text === "" ? [] : JSON.parse(text)
        } catch (error) {
            calendarEvents = []
        }
    }

    function saveCalendarEvents() {
        calendarFile.setText(JSON.stringify(calendarEvents, null, 2) + "\n")
    }

    function addCalendarEvent() {
        var title = calendarEventTitle.trim()
        if (title === "")
            return

        var events = calendarEvents.slice()
        events.push({
            id: Date.now() + "-" + Math.floor(Math.random() * 1000),
            date: calendarSelectedDate || todayIso(),
            time: calendarEventTime.trim(),
            title: title,
            note: calendarEventNote.trim()
        })
        calendarEvents = events
        calendarEventTitle = ""
        calendarEventNote = ""
        saveCalendarEvents()
    }

    function removeCalendarEvent(id) {
        var events = []
        for (var i = 0; i < calendarEvents.length; ++i) {
            if (calendarEvents[i].id !== id)
                events.push(calendarEvents[i])
        }
        calendarEvents = events
        saveCalendarEvents()
    }

    function loadSidebarShortcuts() {
        try {
            var text = sidebarShortcutsFile.text().trim()
            var data = text === "" ? [] : JSON.parse(text)
            sidebarShortcuts = Array.isArray(data) ? data : (Array.isArray(data.shortcuts) ? data.shortcuts : [])
            var defaultOrder = ["terminal", "files", "spotify", "vencord", "zen", "audio", "lock"]
            sidebarActionOrder = normalizedActionOrder(!Array.isArray(data) && Array.isArray(data.actionOrder) ? data.actionOrder : defaultOrder)
            sidebarActionOverrides = !Array.isArray(data) && data.actionOverrides ? data.actionOverrides : ({})
            sidebarSectionOrder = normalizedSectionOrder(Array.isArray(data.sectionOrder) ? data.sectionOrder : [])
        } catch (error) {
            sidebarShortcuts = []
            sidebarActionOrder = normalizedActionOrder(["terminal", "files", "spotify", "vencord", "zen", "audio", "lock"])
            sidebarActionOverrides = ({})
            sidebarSectionOrder = normalizedSectionOrder([])
        }
    }

    function saveSidebarShortcuts() {
        sidebarShortcutsFile.setText(JSON.stringify({
            shortcuts: sidebarShortcuts,
            actionOrder: sidebarActionOrder,
            actionOverrides: sidebarActionOverrides,
            sectionOrder: sidebarSectionOrder
        }, null, 2) + "\n")
    }

    function normalizedActionOrder(order) {
        var defaults = ["terminal", "files", "spotify", "vencord", "zen", "audio", "lock"]
        var valid = ({})
        var result = []
        for (var i = 0; i < defaults.length; ++i)
            valid[defaults[i]] = true
        for (var j = 0; j < sidebarShortcuts.length; ++j)
            valid["custom:" + sidebarShortcuts[j].id] = true
        for (var k = 0; k < order.length; ++k) {
            var key = String(order[k])
            if (valid[key] && result.indexOf(key) === -1)
                result.push(key)
        }
        for (var s = 0; s < sidebarShortcuts.length; ++s) {
            var customKey = "custom:" + sidebarShortcuts[s].id
            if (result.indexOf(customKey) === -1)
                result.push(customKey)
        }
        return result
    }

    function normalizedSectionOrder(order) {
        var defaults = ["overview", "media", "workspaces", "actions"]
        var result = []
        for (var i = 0; i < order.length; ++i) {
            var key = String(order[i])
            if (defaults.indexOf(key) !== -1 && result.indexOf(key) === -1)
                result.push(key)
        }
        for (var j = 0; j < defaults.length; ++j) {
            if (result.indexOf(defaults[j]) === -1)
                result.push(defaults[j])
        }
        return result
    }

    function sidebarActions() {
        var definitions = {
            terminal: { key: "terminal", title: "Terminal", icon: "", accent: Theme.neon, command: "kitty" },
            files: { key: "files", title: "File", icon: "", accent: Theme.success, command: "thunar" },
            spotify: { key: "spotify", title: "Spotify", icon: "", accent: Theme.success, command: "spotify" },
            vencord: { key: "vencord", title: "Vencord", icon: "", accent: Theme.violet, command: "vesktop" },
            zen: { key: "zen", title: "Zen", icon: "󰖟", accent: Theme.neon, command: "zen-browser", browser: true },
            audio: { key: "audio", title: "Audio", icon: "󰕾", accent: Theme.warning, command: "pavucontrol" },
            lock: { key: "lock", title: "Lock", icon: "", accent: Theme.magenta, command: "swaylock -f" }
        }
        for (var definitionKey in definitions) {
            var override = sidebarActionOverrides[definitionKey]
            if (!override)
                continue
            definitions[definitionKey].title = String(override.title || definitions[definitionKey].title)
            definitions[definitionKey].command = String(override.command || definitions[definitionKey].command)
            definitions[definitionKey].icon = String(override.icon || definitions[definitionKey].icon)
            definitions[definitionKey].iconSource = String(override.iconSource || "")
        }
        for (var i = 0; i < sidebarShortcuts.length; ++i) {
            var shortcut = sidebarShortcuts[i]
            definitions["custom:" + shortcut.id] = {
                key: "custom:" + shortcut.id,
                customId: shortcut.id,
                title: String(shortcut.title || "Shortcut"),
                icon: String(shortcut.icon || "󰘳"),
                iconSource: String(shortcut.iconSource || ""),
                accent: Theme.neon,
                command: String(shortcut.command || ""),
                custom: true
            }
        }
        var actions = []
        for (var j = 0; j < sidebarActionOrder.length; ++j) {
            var action = definitions[sidebarActionOrder[j]]
            if (action)
                actions.push(action)
        }
        return actions
    }

    function moveSidebarAction(from, to) {
        if (from === to || from < 0 || to < 0 || from >= sidebarActionOrder.length || to >= sidebarActionOrder.length)
            return
        var order = sidebarActionOrder.slice()
        var moved = order.splice(from, 1)[0]
        order.splice(to, 0, moved)
        sidebarActionOrder = order
        saveSidebarShortcuts()
    }

    function moveSidebarSection(from, to) {
        if (from === to || from < 0 || to < 0 || from >= sidebarSectionOrder.length || to >= sidebarSectionOrder.length)
            return
        var order = sidebarSectionOrder.slice()
        var moved = order.splice(from, 1)[0]
        order.splice(to, 0, moved)
        sidebarSectionOrder = order
        saveSidebarShortcuts()
    }

    function addSidebarShortcut(title, command, icon, iconSource) {
        var shortcuts = sidebarShortcuts.slice()
        var shortcutId = Date.now() + "-" + Math.floor(Math.random() * 1000)
        shortcuts.push({ id: shortcutId, title: String(title), command: String(command), icon: String(icon || "󰘳"), iconSource: String(iconSource || "") })
        sidebarShortcuts = shortcuts
        var order = sidebarActionOrder.slice()
        order.push("custom:" + shortcutId)
        sidebarActionOrder = order
        saveSidebarShortcuts()
    }

    function removeSidebarShortcut(id) {
        var shortcuts = []
        for (var i = 0; i < sidebarShortcuts.length; ++i) {
            if (sidebarShortcuts[i].id !== id)
                shortcuts.push(sidebarShortcuts[i])
        }
        sidebarShortcuts = shortcuts
        var key = "custom:" + id
        var order = sidebarActionOrder.slice()
        var orderIndex = order.indexOf(key)
        if (orderIndex !== -1)
            order.splice(orderIndex, 1)
        sidebarActionOrder = order
        saveSidebarShortcuts()
    }

    function removeSidebarAction(action) {
        if (action.custom) {
            removeSidebarShortcut(action.customId)
            return
        }
        var order = sidebarActionOrder.slice()
        var actionIndex = order.indexOf(String(action.key))
        if (actionIndex !== -1)
            order.splice(actionIndex, 1)
        sidebarActionOrder = order
        saveSidebarShortcuts()
    }

    function updateSidebarAction(actionKey, title, command, icon, iconSource) {
        var key = String(actionKey || "")
        if (key.indexOf("custom:") === 0) {
            var customId = key.substring(7)
            var shortcuts = sidebarShortcuts.slice()
            for (var i = 0; i < shortcuts.length; ++i) {
                if (String(shortcuts[i].id) === customId) {
                    shortcuts[i] = { id: shortcuts[i].id, title: String(title), command: String(command), icon: String(icon || "󰘳"), iconSource: String(iconSource || "") }
                    break
                }
            }
            sidebarShortcuts = shortcuts
        } else {
            var overrides = ({})
            for (var overrideKey in sidebarActionOverrides)
                overrides[overrideKey] = sidebarActionOverrides[overrideKey]
            overrides[key] = { title: String(title), command: String(command), icon: String(icon || "󰘳"), iconSource: String(iconSource || "") }
            sidebarActionOverrides = overrides
        }
        saveSidebarShortcuts()
    }

    function launchSidebarShortcut(command) {
        Quickshell.execDetached(["sh", "-c", String(command)])
    }

    function openCalendar(monitorName) {
        var target = monitorName || currentMonitorName()
        if (calendarOpen && calendarMonitorName === target) {
            calendarOpen = false
            return
        }
        var now = new Date()
        calendarMonitorName = target
        calendarMonth = now.getMonth()
        calendarYear = now.getFullYear()
        calendarSelectedDate = todayIso()
        calendarOpen = true
        launcherOpen = false
        loadCalendarEvents()
    }

    function shiftCalendarMonth(delta) {
        var date = new Date(calendarYear, calendarMonth + delta, 1)
        calendarMonth = date.getMonth()
        calendarYear = date.getFullYear()
    }

    function checkCalendarNotifications() {
        var now = new Date()
        var current = now.getTime()
        var sent = notifiedEvents
        for (var i = 0; i < calendarEvents.length; ++i) {
            var event = calendarEvents[i]
            if (!event.time || event.time.length < 4)
                continue
            var due = new Date(event.date + "T" + event.time + ":00")
            var diff = due.getTime() - current
            if (diff >= 0 && diff <= 60000 && !sent[event.id]) {
                sent[event.id] = true
                var summary = "Calendar: " + event.title
                var body = event.date + " " + event.time + (event.note ? " - " + event.note : "")
                run("notify-send " + "'" + summary.replace(/'/g, "'\\''") + "' " + "'" + body.replace(/'/g, "'\\''") + "'")
            }
        }
        notifiedEvents = sent
    }

    function updateSwayState() {
        swayMode.running = true
    }

    function workspaceState(number) {
        return I3.findWorkspaceByName(String(number))
    }

    function shortText(text, max) {
        if (!text)
            return ""
        return text.length > max ? text.substring(0, max - 1) + "..." : text
    }

    function visualBand(index) {
        if (!visualBands || index >= visualBands.length)
            return 0
        return Math.max(0, Math.min(100, Number(visualBands[index]) || 0))
    }

    function currentMonitorName() {
        if (Hyprland.focusedMonitor)
            return Hyprland.focusedMonitor.name
        return ""
    }

    function toggleLauncher(monitorName) {
        var target = monitorName || currentMonitorName()
        if (launcherOpen && launcherMonitorName === target) {
            closeLauncher()
            return
        }

        launcherMonitorName = target
        launcherOpen = true
        calendarOpen = false
        if (launcherOpen) {
            launcherQuery = ""
            launcherCategory = "All"
            appsLoading = true
            appListProcess.running = true
        }
    }

    function closeLauncher() {
        launcherOpen = false
        launcherMonitorName = ""
        launcherQuery = ""
        launcherCategory = "All"
        launcherMode = "apps"
        appsLoading = false
        cancelAurSearch()
    }

    function startAurSearch(query) {
        aurDebounceQuery = query
        if (query.length < 2) {
            aurSearching = false
            aurResults = []
            aurError = ""
            aurSearchGeneration++
            return
        }
        aurDebounceTimer.restart()
    }

    function cancelAurSearch() {
        aurDebounceTimer.stop()
        aurSearching = false
        aurSearchGeneration++
        aurSearchProcess.running = false
    }

    function executeAurSearch(query) {
        aurSearchGeneration++
        var gen = aurSearchGeneration
        aurQuery = query
        aurSearching = true
        aurError = ""
        aurResults = []
        aurSearchProcess.command = ["python3", Quickshell.shellPath("paru_search.py"), "search", query]
        aurSearchProcess.running = true
    }

    function openAurTerminal(args) {
        Quickshell.execDetached(args)
    }

    function filteredApps() {
        var query = launcherQuery.toLowerCase().trim()
        var out = []
        for (var i = 0; i < appList.length; ++i) {
            var app = appList[i]
            var categoryMatches = launcherCategory === "All" || app.category === launcherCategory
            var queryMatches = query === "" || app.name.toLowerCase().indexOf(query) !== -1 || app.id.toLowerCase().indexOf(query) !== -1 || app.category.toLowerCase().indexOf(query) !== -1
            if (categoryMatches && queryMatches)
                out.push(app)
        }
        return out
    }

    function launcherCategories() {
        var preferred = ["All", "Game", "Media", "Web", "Dev", "System", "Art", "Work", "App"]
        var out = []
        for (var i = 0; i < preferred.length; ++i) {
            if (preferred[i] === "All" || categoryCount(preferred[i]) > 0)
                out.push(preferred[i])
        }
        return out
    }

    function categoryCount(category) {
        if (category === "All")
            return appList.length
        var count = 0
        for (var i = 0; i < appList.length; ++i) {
            if (appList[i].category === category)
                count++
        }
        return count
    }

    function categoryIcon(category) {
        if (category === "All")
            return "󰀻"
        if (category === "Game")
            return "󰊴"
        if (category === "Media")
            return "󰝚"
        if (category === "Web")
            return "󰖟"
        if (category === "Dev")
            return "󰅩"
        if (category === "System")
            return "󰒓"
        if (category === "Art")
            return "󰏘"
        if (category === "Work")
            return "󰈙"
        return "󰏖"
    }

    function launchApp(appId) {
        closeLauncher()
        run("gtk-launch " + "'" + String(appId).replace(/'/g, "'\\''") + "'")
    }

    function appCategory(raw, name, id) {
        var text = String(raw || "") + ";" + String(name || "") + ";" + String(id || "")
        if (text.match(/Game|Steam|Lutris|Prism|Minecraft|Aimlabs/i))
            return "Game"
        if (text.match(/AudioVideo|Audio|Video|Player|Music|Spotify|OBS|Kdenlive/i))
            return "Media"
        if (text.match(/Development|IDE|Code|Git|Qt|Designer/i))
            return "Dev"
        if (text.match(/Graphics|Photography|Image|Gimp|Krita|Blender/i))
            return "Art"
        if (text.match(/Network|WebBrowser|Chat|Discord|Vesktop|Telegram|WhatsApp|Firefox/i))
            return "Web"
        if (text.match(/Utility|Settings|System|Monitor|Terminal|Console|FileManager/i))
            return "System"
        if (text.match(/Office|TextEditor|Education|Science/i))
            return "Work"
        return "App"
    }

    function categoryColor(category) {
        if (category === "Game")
            return Theme.electricBlue
        if (category === "Media")
            return Theme.violet
        if (category === "Dev")
            return Theme.success
        if (category === "Art")
            return Theme.magenta
        if (category === "Web")
            return Theme.neon
        if (category === "System")
            return Theme.warning
        if (category === "Work")
            return Theme.textSecondary
        return Theme.neonSoft
    }

    function resolveIconSource(icon) {
        var value = String(icon || "")
        if (value === "")
            return ""
        if (value.charAt(0) === "/")
            return "file://" + value
        // check=true yields "" for unknown icons; otherwise Qt draws its pink/black "missing texture" tile
        var found = Quickshell.iconPath(value, true)
        if (found !== "")
            return found
        return Quickshell.iconPath("application-x-executable", true)
    }

    Process {
        id: commandRunner
        running: false
    }

    FileView {
        id: calendarFile
        path: "/home/elia1995/.config/quickshell/calendar_events.json"
        preload: true
        watchChanges: true
        printErrors: false
        onLoaded: shell.loadCalendarEvents()
        onFileChanged: shell.loadCalendarEvents()
    }

    FileView {
        id: sidebarShortcutsFile
        path: "/home/elia1995/.config/quickshell/sidebar_shortcuts.json"
        preload: true
        watchChanges: false
        printErrors: false
        onLoaded: shell.loadSidebarShortcuts()
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            shell.toggleLauncher()
        }

        function open(): void {
            shell.launcherMonitorName = shell.currentMonitorName()
            shell.launcherOpen = true
            shell.calendarOpen = false
            shell.launcherQuery = ""
            shell.launcherCategory = "All"
            shell.launcherMode = "apps"
            shell.cancelAurSearch()
            shell.appsLoading = true
            appListProcess.running = true
        }

        function close(): void {
            shell.closeLauncher()
        }
    }

    Process {
        id: appListProcess
        command: ["/home/elia1995/.config/quickshell/apps.sh"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var apps = []
                var lines = this.text.trim().split("\n")
                for (var i = 0; i < lines.length; ++i) {
                    var parts = lines[i].split("\t")
                    if (parts.length >= 2)
                        apps.push({ name: parts[0], id: parts[1], icon: parts.length >= 3 ? parts[2] : "", category: shell.appCategory(parts.length >= 4 ? parts[3] : "", parts[0], parts[1]), exec: parts.length >= 5 ? parts[4] : "gtk-launch '" + String(parts[1]).replace(/'/g, "'\\''") + "'" })
                }
                shell.appList = apps
                shell.appsLoading = false
            }
        }
    }

    Process {
        id: aurSearchProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var gen = shell.aurSearchGeneration
                try {
                    var data = JSON.parse(this.text)
                    if (gen !== shell.aurSearchGeneration) return
                    if (data.ok) {
                        shell.aurResults = data.results
                        shell.aurError = ""
                    } else {
                        shell.aurResults = []
                        shell.aurError = data.error || "Search failed"
                    }
                } catch (e) {
                    if (gen !== shell.aurSearchGeneration) return
                    shell.aurResults = []
                    shell.aurError = "Failed to parse results"
                }
                shell.aurSearching = false
            }
        }
        stderr: SplitParser {
            onRead: function(line) {
                // suppress stderr from showing in logs
            }
        }
        onExited: {
            if (shell.aurSearching) {
                shell.aurSearching = false
            }
        }
    }

    Timer {
        id: aurDebounceTimer
        interval: 350
        repeat: false
        onTriggered: shell.executeAurSearch(shell.aurDebounceQuery)
    }

    Process {
        id: swayMode
        command: ["swaymsg", "-t", "get_binding_state"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var state = JSON.parse(this.text)
                    shell.modeText = state.name && state.name !== "default" ? state.name : ""
                } catch (error) {
                    shell.modeText = ""
                }
            }
        }
    }

    Process {
        id: volumeProcess
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var text = this.text.trim()
                var match = text.match(/([0-9.]+)/)
                shell.volumeMuted = text.indexOf("MUTED") !== -1
                shell.volumeText = match ? Math.round(parseFloat(match[1]) * 100) + "%" : "--%"
            }
        }
    }

    Process {
        id: networkProcess
        command: ["sh", "-c", "state=$(cat /sys/class/net/enp8s0/operstate 2>/dev/null); [ \"$state\" = up ] && printf enp8s0 || printf Offline"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: shell.networkText = this.text.trim() === "" ? "Offline" : shell.shortText(this.text.trim(), 18)
        }
    }

    Process {
        id: playerProcess
        command: ["sh", "-c", "status=$(playerctl status 2>/dev/null || true); title=$(playerctl metadata --format '{{artist}} - {{title}}' 2>/dev/null || true); printf '%s\\n%s' \"$status\" \"$title\""]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                shell.audioPlaying = lines[0] === "Playing"
                shell.trackText = lines.length > 1 && lines[1] !== "" ? shell.shortText(lines[1], 34) : (shell.audioPlaying ? "Playing" : "No player")
            }
        }
    }

    Process {
        id: visualizerProcess
        command: ["/home/elia1995/.config/quickshell/audio_visualizer.py"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                var parts = line.trim().split(",")
                if (parts.length < 18)
                    return

                var bands = []
                for (var i = 0; i < 18; ++i)
                    bands.push(parseInt(parts[i]) || 0)
                shell.visualBands = bands
            }
        }
        onExited: restartVisualizer.running = true
    }

    Timer { interval: 1000; repeat: true; running: true; onTriggered: updateClock() }
    Timer { interval: 1000; repeat: true; running: true; onTriggered: updateSwayState() }
    Timer { interval: 3000; repeat: true; running: true; onTriggered: volumeProcess.running = true }
    Timer { interval: 10000; repeat: true; running: true; onTriggered: networkProcess.running = true }
    Timer { interval: 2000; repeat: true; running: true; onTriggered: playerProcess.running = true }
    Timer { id: restartVisualizer; interval: 1000; repeat: false; onTriggered: visualizerProcess.running = true }
    Timer { id: mediaRefreshTimer; interval: 180; repeat: false; onTriggered: playerProcess.running = true }
    Timer { interval: 30000; repeat: true; running: true; onTriggered: checkCalendarNotifications() }

    Component.onCompleted: {
        updateClock()
        I3.refreshWorkspaces()
        updateSwayState()
        volumeProcess.running = true
        networkProcess.running = true
        playerProcess.running = true
        appsLoading = true
        appListProcess.running = true
        loadCalendarEvents()
        loadSidebarShortcuts()
    }

    component GlassModule: Rectangle {
        id: module
        property bool accent: false
        property color fg: Theme.textPrimary
        property alias content: moduleContent.data

        implicitWidth: moduleContent.implicitWidth + 28
        implicitHeight: 28
        radius: Theme.radiusMedium
        color: accent ? Theme.alpha(Theme.neon, 0.16) : Theme.alpha(Theme.panel, 0.94)
        border.width: 1
        border.color: accent ? Theme.alpha(Theme.neonStrong, 0.72) : Theme.alpha(Theme.neonDark, 0.58)

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Theme.alpha(Theme.textPrimary, 0.035)
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: Math.min(parent.width * 0.36, 44)
            height: 1
            color: Theme.alpha(accent ? Theme.neonStrong : Theme.neonSoft, accent ? 0.72 : 0.30)
        }

        Row {
            id: moduleContent
            anchors.centerIn: parent
            spacing: 7
        }
    }

    component Label: Text {
        color: Theme.textPrimary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.weight: 700
        verticalAlignment: Text.AlignVCenter
    }

    component StartButton: NeonButton {
        implicitWidth: 112
        implicitHeight: 28
        accentColor: Theme.neonStrong
        backgroundColor: Theme.panelRaised
        active: true
        glowEnabled: true

        Row {
            anchors.centerIn: parent
            spacing: 8
            Text {
                text: ""
                color: Theme.neonStrong
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.weight: 700
                verticalAlignment: Text.AlignVCenter
            }
            Label { text: "START"; color: Theme.textPrimary; font.pixelSize: Theme.fontSize }
        }
    }

    component TrayButton: Rectangle {
        required property var trayItem
        required property var panelWindow

        width: 24
        height: 24
        radius: Theme.radiusSmall
        color: trayMouse.containsMouse ? Theme.panelHover : "transparent"
        border.width: trayMouse.containsMouse ? 1 : 0
        border.color: Theme.alpha(Theme.neon, 0.55)
        scale: trayMouse.pressed ? 0.97 : trayMouse.containsMouse ? 1.04 : 1.0

        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        function openMenu() {
            menuPopup.visible = !menuPopup.visible
        }

        QsMenuOpener {
            id: rootMenu
            menu: trayItem.menu || null
        }

        HyprlandFocusGrab {
            windows: [menuPopup]
            active: menuPopup.visible
            onCleared: menuPopup.visible = false
        }

        // Themed replacement for the native Qt menu: two levels (submenus expand inline).
        PopupWindow {
            id: menuPopup
            anchor.window: panelWindow || null
            anchor.item: trayMouse
            anchor.edges: Edges.Bottom
            anchor.gravity: Edges.Bottom | Edges.Left
            anchor.margins.top: 8
            implicitWidth: 270
            implicitHeight: menuBody.implicitHeight + 16
            color: "transparent"
            visible: false

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusMedium
                color: Theme.alpha(Theme.panel, 0.96)
                border.width: 1
                border.color: Theme.alpha(Theme.neon, 0.7)

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    width: 60; height: 1
                    color: Theme.alpha(Theme.neonStrong, 0.8)
                }

                Column {
                    id: menuBody
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 2

                    Repeater {
                        model: rootMenu.children
                        delegate: Column {
                            id: entryCol
                            required property var modelData
                            property bool expanded: false
                            width: menuBody.width
                            spacing: 2

                            QsMenuOpener {
                                id: subMenu
                                menu: entryCol.modelData.hasChildren && entryCol.expanded ? entryCol.modelData : null
                            }

                            TrayMenuRow {
                                width: parent.width
                                entry: entryCol.modelData
                                expanded: entryCol.expanded
                                onActivated: {
                                    if (entry.hasChildren) entryCol.expanded = !entryCol.expanded
                                    else { entry.triggered(); menuPopup.visible = false }
                                }
                            }

                            Repeater {
                                model: subMenu.children
                                delegate: TrayMenuRow {
                                    required property var modelData
                                    width: entryCol.width
                                    entry: modelData
                                    indent: 18
                                    onActivated: { modelData.triggered(); menuPopup.visible = false }
                                }
                            }
                        }
                    }
                }
            }
        }

        function iconSource() {
            var icon = String(trayItem.icon || "")
            if (icon.toLowerCase().indexOf("spotify") !== -1)
                return "file:///usr/share/icons/hicolor/32x32/apps/spotify.png"
            return icon.split("?")[0]
        }

        IconImage {
            id: trayIcon
            anchors.centerIn: parent
            implicitSize: 18
            width: 18
            height: 18
            source: parent.iconSource()
            asynchronous: true
        }

        Label {
            anchors.centerIn: parent
            visible: trayIcon.status === Image.Error
            text: "•"
            color: Theme.neon
            font.pixelSize: 18
        }

        MouseArea {
            id: trayMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    openMenu()
                } else if (trayItem.onlyMenu) {
                    openMenu()
                } else {
                    trayItem.activate()
                }
            }
        }
    }

    component Visualizer: Rectangle {
        implicitWidth: 126
        implicitHeight: 28
        radius: Theme.radiusMedium
        color: Theme.alpha(Theme.panel, 0.94)
        border.width: 1
        border.color: shell.audioPlaying ? Theme.alpha(Theme.neon, 0.62) : Theme.alpha(Theme.neonDark, 0.44)

        Row {
            anchors.centerIn: parent
            spacing: 3

            Repeater {
                model: 18
                Rectangle {
                    property int bandValue: shell.visualBand(index)
                    width: 4
                    height: 4 + bandValue / 100 * 21
                    radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.alpha(index % 4 === 0 ? Theme.neonStrong : Theme.neon, 0.25 + bandValue / 100 * 0.75)


                }
            }
        }
    }

    component MiniVisualizer: Rectangle {
        implicitWidth: 132
        implicitHeight: 24
        radius: Theme.radiusSmall
        color: Theme.alpha(Theme.background, 0.72)
        border.width: 1
        border.color: Theme.alpha(Theme.neonDark, 0.52)

        Row {
            anchors.centerIn: parent
            spacing: 2

            Repeater {
                model: 18
                Rectangle {
                    property int bandValue: shell.visualBand(index)
                    width: 3
                    height: 3 + bandValue / 100 * 16
                    radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.alpha(index % 4 === 0 ? Theme.neonStrong : Theme.neonSoft, 0.24 + bandValue / 100 * 0.70)


                }
            }
        }
    }

    component MediaButton: NeonButton {
        id: mediaButton
        required property string icon
        required property string command

        width: 24
        height: 24
        accentColor: Theme.neon
        backgroundColor: Theme.panelRaised
        onClicked: shell.runMediaCommand(command)

        Label {
            anchors.centerIn: parent
            text: icon
            color: mediaButton.hovered ? Theme.neonStrong : Theme.textSecondary
            font.pixelSize: 12
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: sidebarWindow
            required property var modelData
            property bool contextMenuOpen: false
            property bool shortcutEditorOpen: false
            property var editingAction: null
            property bool pinned: false
            readonly property string monitorName: I3.monitorFor(modelData) ? I3.monitorFor(modelData).name : modelData.name
            readonly property real sidebarScale: Theme.scaleForMonitor(monitorName)
            readonly property bool expanded: sidebarHover.hovered || contextMenuOpen || shortcutEditorOpen || pinned

            screen: modelData
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            implicitWidth: expanded ? 310 * sidebarScale : 7 * sidebarScale
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell-sidebar"
            WlrLayershell.exclusiveZone: 0
            WlrLayershell.keyboardFocus: shortcutEditorOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            Behavior on implicitWidth {
                NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic }
            }

            Item {
                anchors.fill: parent

                HoverHandler { id: sidebarHover }

                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: (sidebarWindow.expanded ? 3 : 4) * sidebarWindow.sidebarScale
                    height: (sidebarWindow.expanded ? 120 : 92) * sidebarWindow.sidebarScale
                    radius: 3 * sidebarWindow.sidebarScale
                    color: Theme.alpha(Theme.neonStrong, sidebarWindow.expanded ? 0.34 : 0.88)

                    Behavior on height { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: Theme.animNormal } }
                }

                NeonPanel {
                    id: sidebarPanel
                    x: sidebarWindow.expanded ? 8 * sidebarWindow.sidebarScale : -294 * sidebarWindow.sidebarScale
                    anchors.verticalCenter: parent.verticalCenter
                    width: 292
                    height: (parent.height - 112 * sidebarWindow.sidebarScale) / sidebarWindow.sidebarScale
                    scale: sidebarWindow.sidebarScale
                    transformOrigin: Item.Left
                    cornerRadius: Theme.radiusLarge
                    panelColor: Theme.alpha(Theme.backgroundSecondary, 0.98)
                    accentColor: Theme.neon
                    glowStrength: 0.22
                    hudDecorations: true
                    decorationVariant: 1
                    clip: true
                    opacity: sidebarWindow.expanded ? 1 : 0

                    Behavior on x { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 16
                        contentWidth: width
                        contentHeight: sidebarColumn.implicitHeight
                        clip: true
                        interactive: contentHeight > height
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: sidebarColumn
                            width: parent.width
                            spacing: 10

                            Item {
                                width: parent.width
                                height: 68

                                NeonPanel {
                                    width: 46
                                    height: 46
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    cornerRadius: Theme.radiusMedium
                                    panelColor: Theme.panelRaised
                                    accentColor: Theme.neonStrong
                                    glowStrength: 0.16

                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        color: Theme.neonStrong
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 22
                                        font.weight: 900
                                    }
                                }

                                Column {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 58
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        text: shell.timeText.substring(0, 5)
                                        color: Theme.textPrimary
                                        font.family: Theme.technicalFontFamily
                                        font.pixelSize: 24
                                        font.weight: 900
                                    }

                                    Text {
                                        text: shell.dateText
                                        color: Theme.textSecondary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: 700
                                    }
                                }

                                NeonButton {
                                    id: pinButton
                                    width: 30
                                    height: 30
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.topMargin: 8
                                    accentColor: sidebarWindow.pinned ? Theme.success : Theme.neon
                                    active: sidebarWindow.pinned
                                    onClicked: sidebarWindow.pinned = !sidebarWindow.pinned

                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        color: sidebarWindow.pinned ? Theme.success : Theme.textSecondary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        rotation: sidebarWindow.pinned ? 0 : -25
                                        Behavior on rotation { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }

                            NeonSeparator { width: parent.width; accentColor: Theme.neon }

                            SidebarSections {
                                width: parent.width
                                height: implicitHeight
                                sectionOrder: shell.sidebarSectionOrder
                                actions: shell.sidebarActions()
                                networkOnline: shell.networkText !== "Offline"
                                volumeMuted: shell.volumeMuted
                                volumeText: shell.volumeText
                                audioPlaying: shell.audioPlaying
                                trackText: shell.trackText
                                focusedWorkspaceNumber: shell.focusedWorkspaceNumber
                                onSectionMoveRequested: function(from, to) { shell.moveSidebarSection(from, to) }
                                onActionMoveRequested: function(from, to) { shell.moveSidebarAction(from, to) }
                                onActionTriggered: function(action) { shell.launchSidebarShortcut(action.command) }
                                onRemoveActionRequested: function(action) { shell.removeSidebarAction(action) }
                                onEditActionRequested: function(action) {
                                    sidebarWindow.editingAction = action
                                    sidebarWindow.shortcutEditorOpen = true
                                }
                                onRemoveShortcutRequested: function(shortcutId) { shell.removeSidebarShortcut(shortcutId) }
                                onPrivateBrowserRequested: Quickshell.execDetached(["zen-browser", "--private-window"])
                                onWorkspaceRequested: function(number) { shell.gotoWorkspace(number) }
                                onMediaCommandRequested: function(command) { shell.runMediaCommand(command) }
                                onEditorRequested: {
                                    sidebarWindow.editingAction = null
                                    sidebarWindow.shortcutEditorOpen = true
                                }
                                onMenuOpenChanged: function(open) { sidebarWindow.contextMenuOpen = open }
                            }
                        }
                    }

                    SidebarShortcutEditor {
                        id: shortcutEditor
                        anchors.fill: parent
                        z: 20
                        visible: sidebarWindow.shortcutEditorOpen
                        apps: shell.appList
                        editAction: sidebarWindow.editingAction
                        onCloseRequested: {
                            sidebarWindow.shortcutEditorOpen = false
                            sidebarWindow.editingAction = null
                        }
                        onSaveRequested: function(shortcutTitle, shortcutCommand, shortcutIcon, shortcutIconSource) {
                            if (sidebarWindow.editingAction)
                                shell.updateSidebarAction(sidebarWindow.editingAction.key, shortcutTitle, shortcutCommand, shortcutIcon, shortcutIconSource)
                            else
                                shell.addSidebarShortcut(shortcutTitle, shortcutCommand, shortcutIcon, shortcutIconSource)
                            sidebarWindow.shortcutEditorOpen = false
                            sidebarWindow.editingAction = null
                        }
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panelWindow
            required property var modelData
            readonly property string monitorName: I3.monitorFor(modelData) ? I3.monitorFor(modelData).name : modelData.name
            readonly property real uiScale: Theme.scaleForMonitor(monitorName)
            screen: modelData
            anchors.top: true
            anchors.left: true
            anchors.right: true
            implicitHeight: Theme.barHeight * uiScale
            margins.top: 8 * uiScale
            margins.left: 12 * uiScale
            margins.right: 12 * uiScale
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            Component {
                id: mod_workspaces
        GlassModule {
            content: Item {
                id: workspaceRow
                implicitWidth: wsRow.implicitWidth
                implicitHeight: 22

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: function(event) {
                        var cur = Math.max(1, shell.focusedWorkspaceNumber)
                        var next = Math.max(1, Math.min(10, cur + (event.angleDelta.y < 0 ? 1 : -1)))
                        if (next !== cur)
                            shell.gotoWorkspace(next)
                    }
                }

                Row {
                    id: wsRow
                    spacing: 4

                    Repeater {
                        model: 10
                        Item {
                            id: slot
                            property bool focused: shell.focusedWorkspaceNumber === index + 1
                            property bool shownElsewhere: !!shell.wsVisible[index + 1] && !focused
                            property bool urgent: false
                            property bool occupied: (shell.wsOccupied[index + 1] || 0) > 0
                            property bool hovered: slotMouse.containsMouse

                            width: focused ? 46 : 26
                            height: 22
                            Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                            // soft halo behind the active workspace
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -3
                                radius: 14
                                color: Theme.alpha(Theme.neonStrong, 0.16)
                                opacity: slot.focused ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 220 } }
                            }

                            Rectangle {
                                id: slotBg
                                anchors.fill: parent
                                radius: 11
                                border.width: slot.focused ? 0 : 1
                                border.color: slot.urgent ? Theme.alpha(Theme.danger, 0.8)
                                    : slot.shownElsewhere ? Theme.alpha(Theme.neonSoft, 0.7)
                                    : slot.hovered ? Theme.alpha(Theme.neon, 0.45) : "transparent"
                                color: slot.urgent ? Theme.alpha(Theme.danger, 0.2)
                                    : slot.hovered && !slot.focused ? Theme.alpha(Theme.neon, 0.12)
                                    : slot.occupied && !slot.focused ? Theme.alpha(Theme.highlight, 0.55) : "transparent"
                                gradient: slot.focused ? activeFill : null
                                Behavior on color { ColorAnimation { duration: 160 } }
                                Behavior on border.color { ColorAnimation { duration: 160 } }

                                Gradient {
                                    id: activeFill
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: Theme.neonStrong }
                                    GradientStop { position: 1.0; color: Theme.electricBlue }
                                }
                            }

                            Label {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: slot.occupied && !slot.focused ? -1 : 0
                                text: index + 1
                                font.pixelSize: slot.focused ? 14 : 13
                                font.bold: slot.focused
                                color: slot.focused ? Theme.background
                                    : slot.urgent ? Theme.danger
                                    : slot.hovered ? Theme.textPrimary
                                    : slot.occupied ? Theme.textSecondary
                                    : Theme.alpha(Theme.textMuted, 0.55)
                                Behavior on color { ColorAnimation { duration: 160 } }
                            }

                            // occupied marker
                            Rectangle {
                                width: 4; height: 4; radius: 2
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 1
                                color: Theme.neon
                                opacity: slot.occupied && !slot.focused ? 0.85 : 0
                                Behavior on opacity { NumberAnimation { duration: 160 } }
                            }

                            MouseArea {
                                id: slotMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: shell.gotoWorkspace(index + 1)
                            }
                        }
                    }
                }
            }
        }
            }

            Component {
                id: mod_elsewhere
        GlassModule {
            visible: shell.windowsElsewhere > 0
            accent: true
            content: Row {
                spacing: 6
                Label {
                    text: "\udb81\udd9f"
                    color: Theme.neonStrong
                    font.pixelSize: 14
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    text: shell.windowsElsewhere + " elsewhere"
                    color: Theme.textPrimary
                    font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
            }

            Component {
                id: mod_mode
        GlassModule {
            visible: shell.modeText !== ""
            fg: Theme.success
            content: Label { text: shell.modeText; color: Theme.success; font.italic: true }
        }
            }

            Component {
                id: mod_start
        StartButton {
            onClicked: shell.toggleLauncher(panelWindow.monitorName)
        }
            }

            Component {
                id: mod_tray
        GlassModule {
            implicitWidth: trayRow.implicitWidth + 24
            content: Row {
                id: trayRow
                spacing: 4
                Repeater {
                    model: SystemTray.items
                    TrayButton {
                        required property var modelData
                        trayItem: modelData
                        panelWindow: panelWindow
                    }
                }
            }
        }
            }

            Component {
                id: mod_network
        GlassModule {
            content: Row {
                spacing: 7
                Label { text: shell.networkText === "Offline" ? "󰤮" : "󰈀"; color: shell.networkText === "Offline" ? Theme.textMuted : Theme.neon }
                Label { text: shell.networkText; color: shell.networkText === "Offline" ? Theme.textMuted : Theme.textSecondary }
            }
        }
            }

            Component {
                id: mod_visualizer
        Visualizer {}
            }

            Component {
                id: mod_volume
        GlassModule {
            content: Row {
                spacing: 7
                Label { text: shell.volumeMuted ? "" : ""; color: shell.volumeMuted ? Theme.warning : Theme.neon }
                Label { text: shell.volumeMuted ? "Mute" : shell.volumeText; color: shell.volumeMuted ? Theme.warning : Theme.textSecondary }
            }
        }
            }

            Component {
                id: mod_clock
        GlassModule {
            id: clockModule
            accent: true
            content: Row {
                spacing: 8
                Label { text: ""; color: Theme.neonStrong; font.pixelSize: 14 }
                Label { text: shell.dateText + "  " + shell.timeText; color: Theme.textPrimary; font.pixelSize: 14 }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: shell.openCalendar(panelWindow.monitorName)
            }
        }
            }

            readonly property var modComponents: ({ workspaces: mod_workspaces, elsewhere: mod_elsewhere, mode: mod_mode, start: mod_start, tray: mod_tray, network: mod_network, visualizer: mod_visualizer, volume: mod_volume, clock: mod_clock })
            readonly property var modVisible: ({ elsewhere: shell.windowsElsewhere > 0, mode: shell.modeText !== "" })

            Item {
                anchors.centerIn: parent
                width: parent.width / panelWindow.uiScale
                height: Theme.barHeight
                scale: panelWindow.uiScale
                transformOrigin: Item.Center

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: shell.barLayout.gap
                    Repeater {
                        model: shell.barLayout.left
                        BarSlot { required property var modelData; cfg: modelData; components: panelWindow.modComponents; visibility: panelWindow.modVisible; host: panelWindow }
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: shell.barLayout.gap
                    Repeater {
                        model: shell.barLayout.center
                        BarSlot { required property var modelData; cfg: modelData; components: panelWindow.modComponents; visibility: panelWindow.modVisible; host: panelWindow }
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: shell.barLayout.gap
                    Repeater {
                        model: shell.barLayout.right
                        BarSlot { required property var modelData; cfg: modelData; components: panelWindow.modComponents; visibility: panelWindow.modVisible; host: panelWindow }
                    }
                }
            }

            PopupWindow {
                id: calendarPopup
                visible: shell.calendarOpen && shell.calendarMonitorName === panelWindow.monitorName
                anchor.window: panelWindow
                anchor.rect.x: Math.round(panelWindow.width - implicitWidth - 6)
                anchor.rect.y: 44 * panelWindow.uiScale
                implicitWidth: 520 * panelWindow.uiScale
                implicitHeight: 470 * panelWindow.uiScale
                color: "transparent"

                NeonPanel {
                    width: 520
                    height: 470
                    scale: panelWindow.uiScale
                    transformOrigin: Item.TopLeft
                    cornerRadius: Theme.radiusLarge
                    panelColor: Theme.alpha(Theme.backgroundSecondary, 0.97)
                    accentColor: Theme.neon
                    glowStrength: 0.24
                    hudDecorations: true
                    decorationVariant: 1

                    Row {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 14

                        Column {
                            width: 256
                            height: parent.height
                            spacing: 12

                            Row {
                                width: parent.width
                                height: 32
                                spacing: 8

                                Rectangle {
                                    width: 24
                                    height: 24
                                    radius: Theme.radiusSmall
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: prevMonthMouse.containsMouse ? Theme.panelHover : Theme.panelRaised
                                    border.width: 1
                                    border.color: Theme.alpha(Theme.neon, prevMonthMouse.containsMouse ? 0.66 : 0.30)
                                    scale: prevMonthMouse.pressed ? 0.97 : prevMonthMouse.containsMouse ? 1.04 : 1.0

                                    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        color: Theme.neon
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                    }

                                    MouseArea {
                                        id: prevMonthMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: shell.shiftCalendarMonth(-1)
                                    }
                                }

                                Text {
                                    width: parent.width - 80
                                    text: shell.monthName(shell.calendarMonth) + " " + shell.calendarYear
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 16
                                    font.weight: 900
                                    horizontalAlignment: Text.AlignHCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Rectangle {
                                    width: 24
                                    height: 24
                                    radius: Theme.radiusSmall
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: nextMonthMouse.containsMouse ? Theme.panelHover : Theme.panelRaised
                                    border.width: 1
                                    border.color: Theme.alpha(Theme.neon, nextMonthMouse.containsMouse ? 0.66 : 0.30)
                                    scale: nextMonthMouse.pressed ? 0.97 : nextMonthMouse.containsMouse ? 1.04 : 1.0

                                    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        color: Theme.neon
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                    }

                                    MouseArea {
                                        id: nextMonthMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: shell.shiftCalendarMonth(1)
                                    }
                                }
                            }

                            Grid {
                                width: parent.width
                                columns: 7
                                rowSpacing: 6
                                columnSpacing: 6

                                Repeater {
                                    model: ["M", "T", "W", "T", "F", "S", "S"]
                                    Text {
                                        required property string modelData
                                        width: 31
                                        height: 20
                                        text: modelData
                                        color: Theme.neonSoft
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: 900
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                Repeater {
                                    model: 42
                                    Rectangle {
                                        property int day: shell.calendarGridDay(index)
                                        property string dateId: day > 0 ? shell.calendarDayDate(day) : ""
                                        property bool selected: dateId !== "" && shell.calendarSelectedDate === dateId
                                        property bool today: dateId !== "" && shell.todayIso() === dateId
                                        property int eventCount: dateId !== "" ? shell.eventsForDate(dateId) : 0

                                        width: 31
                                        height: 31
                                        radius: Theme.radiusSmall
                                        visible: day > 0
                                        color: selected ? Theme.alpha(Theme.neon, 0.22) : dayMouse.containsMouse ? Theme.panelHover : Theme.alpha(Theme.panelRaised, 0.70)
                                        border.width: today || selected ? 1 : 0
                                        border.color: selected ? Theme.neonStrong : Theme.neonSoft
                                        scale: dayMouse.pressed ? 0.97 : dayMouse.containsMouse ? 1.035 : 1.0

                                        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: day
                                            color: selected ? Theme.textPrimary : Theme.textSecondary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.weight: selected || today ? 900 : 700
                                        }

                                        Rectangle {
                                            width: 5
                                            height: 5
                                            radius: 3
                                            visible: eventCount > 0
                                            color: Theme.violet
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: 3
                                        }

                                        MouseArea {
                                            id: dayMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: shell.calendarSelectedDate = dateId
                                        }
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                text: shell.selectedEvents().length + " eventi il " + shell.calendarSelectedDate
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: 700
                                elide: Text.ElideRight
                            }
                        }

                        Column {
                            width: parent.width - 270
                            height: parent.height
                            spacing: 10

                            Text {
                                text: "Agenda"
                                color: Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: 16
                                font.weight: 900
                            }

                            Rectangle {
                                width: parent.width
                                height: 94
                                radius: Theme.radiusMedium
                                color: Theme.alpha(Theme.panelRaised, 0.88)
                                border.width: 1
                                border.color: Theme.alpha(Theme.neonDark, 0.64)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 8

                                    Row {
                                        width: parent.width
                                        height: 28
                                        spacing: 8

                                        Rectangle {
                                            id: timeField
                                            width: 58
                                            height: 28
                                            radius: Theme.radiusSmall
                                            color: Theme.background
                                            border.width: 1
                                            border.color: timeInput.activeFocus ? Theme.neonStrong : Theme.alpha(Theme.neonDark, 0.62)

                                            TextInput {
                                                id: timeInput
                                                anchors.fill: parent
                                                anchors.leftMargin: 9
                                                anchors.rightMargin: 7
                                                text: shell.calendarEventTime
                                                color: Theme.textPrimary
                                                selectionColor: Theme.alpha(Theme.neon, 0.42)
                                                selectedTextColor: Theme.textPrimary
                                                font.family: Theme.technicalFontFamily
                                                font.pixelSize: 12
                                                verticalAlignment: TextInput.AlignVCenter
                                                inputMask: "99:99"
                                                onTextChanged: shell.calendarEventTime = text
                                            }
                                        }

                                        Rectangle {
                                            id: titleField
                                            width: parent.width - 102
                                            height: 28
                                            radius: Theme.radiusSmall
                                            color: Theme.background
                                            border.width: 1
                                            border.color: titleInput.activeFocus ? Theme.neonStrong : Theme.alpha(Theme.neonDark, 0.62)

                                            TextInput {
                                                id: titleInput
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 8
                                                text: shell.calendarEventTitle
                                                color: Theme.textPrimary
                                                selectionColor: Theme.alpha(Theme.neon, 0.42)
                                                selectedTextColor: Theme.textPrimary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.weight: 800
                                                verticalAlignment: TextInput.AlignVCenter
                                                clip: true
                                                onTextChanged: shell.calendarEventTitle = text
                                                Keys.onReturnPressed: shell.addCalendarEvent()
                                            }
                                        }

                                        Rectangle {
                                            width: 28
                                            height: 28
                                            radius: Theme.radiusSmall
                                            color: Theme.alpha(Theme.success, addMouse.containsMouse ? 0.24 : 0.13)
                                            border.width: 1
                                            border.color: Theme.alpha(Theme.success, 0.62)
                                            scale: addMouse.pressed ? 0.97 : addMouse.containsMouse ? 1.04 : 1.0

                                            Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                                            Text {
                                                anchors.centerIn: parent
                                                text: ""
                                                color: Theme.success
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                            }

                                            MouseArea {
                                                id: addMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: shell.addCalendarEvent()
                                            }
                                        }
                                    }

                                    Rectangle {
                                        id: noteField
                                        width: parent.width
                                        height: 28
                                        radius: Theme.radiusSmall
                                        color: Theme.background
                                        border.width: 1
                                        border.color: noteInput.activeFocus ? Theme.neonStrong : Theme.alpha(Theme.neonDark, 0.52)

                                        TextInput {
                                            id: noteInput
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 8
                                            text: shell.calendarEventNote
                                            color: Theme.textSecondary
                                            selectionColor: Theme.alpha(Theme.neon, 0.42)
                                            selectedTextColor: Theme.textPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            verticalAlignment: TextInput.AlignVCenter
                                            clip: true
                                            onTextChanged: shell.calendarEventNote = text
                                        }
                                    }
                                }
                            }

                            Flickable {
                                id: calendarEventFlick
                                width: parent.width
                                height: parent.height - 134
                                contentWidth: width
                                contentHeight: eventColumn.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Column {
                                    id: eventColumn
                                    width: calendarEventFlick.width
                                    spacing: 8

                                    Repeater {
                                        model: shell.selectedEvents()

                                        NeonPanel {
                                            required property var modelData
                                            width: parent.width
                                            height: modelData.note ? 54 : 40
                                            cornerRadius: Theme.radiusMedium
                                            panelColor: eventHover.hovered ? Theme.panelHover : Theme.panelRaised
                                            accentColor: eventHover.hovered ? Theme.neon : Theme.neonDark
                                            glowEnabled: false

                                            Column {
                                                anchors.left: parent.left
                                                anchors.right: deleteButton.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 8
                                                spacing: 2

                                                Text {
                                                    width: parent.width
                                                    text: (modelData.time ? modelData.time + "  " : "") + modelData.title
                                                    color: Theme.textPrimary
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: 900
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    visible: modelData.note
                                                    width: parent.width
                                                    text: modelData.note || ""
                                                    color: Theme.textSecondary
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    font.weight: 700
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            Rectangle {
                                                id: deleteButton
                                                width: 24
                                                height: 24
                                                radius: Theme.radiusSmall
                                                anchors.right: parent.right
                                                anchors.rightMargin: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: deleteMouse.containsMouse ? Theme.alpha(Theme.danger, 0.18) : "transparent"
                                                border.width: deleteMouse.containsMouse ? 1 : 0
                                                border.color: Theme.alpha(Theme.danger, 0.52)
                                                scale: deleteMouse.pressed ? 0.97 : deleteMouse.containsMouse ? 1.04 : 1.0

                                                Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: ""
                                                    color: Theme.danger
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                }

                                                MouseArea {
                                                    id: deleteMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: shell.removeCalendarEvent(modelData.id)
                                                }
                                            }

                                            HoverHandler { id: eventHover }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            PopupWindow {
                id: launcherPopup
                visible: shell.launcherOpen && shell.launcherMonitorName === panelWindow.monitorName
                anchor.window: panelWindow
                anchor.rect.x: Math.round(panelWindow.width / 2 - implicitWidth / 2)
                anchor.rect.y: 44 * panelWindow.uiScale
                implicitWidth: 540 * panelWindow.uiScale
                implicitHeight: 576 * panelWindow.uiScale
                color: "transparent"

                property real openT: 0
                NumberAnimation { id: openAnim; target: launcherPopup; property: "openT"; from: 0; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.1 }

                function ensureVisible() {
                    var pitch = 52, y = shell.launcherIndex * pitch
                    if (y < appFlick.contentY) appFlick.contentY = y
                    else if (y + 44 > appFlick.contentY + appFlick.height) appFlick.contentY = y + 44 - appFlick.height
                }

                onVisibleChanged: {
                    if (visible) {
                        openAnim.restart()
                        Qt.callLater(function() { launcherSearch.forceActiveFocus() })
                    }
                }

                NeonPanel {
                    width: 540
                    height: 576
                    scale: panelWindow.uiScale
                    opacity: Math.min(1, launcherPopup.openT * 1.6)
                    y: (1 - launcherPopup.openT) * -16 * panelWindow.uiScale
                    transformOrigin: Item.TopLeft
                    cornerRadius: Theme.radiusLarge
                    panelColor: Theme.alpha(Theme.backgroundSecondary, 0.98)
                    accentColor: Theme.neonStrong
                    glowEnabled: false
                    innerRing: false
                    borderOpacity: 0.6

                    Column {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        Row {
                            width: parent.width
                            height: 42
                            spacing: 10

                            NeonPanel {
                                width: 42
                                height: 42
                                cornerRadius: Theme.radiusMedium
                                panelColor: Theme.panelRaised
                                accentColor: Theme.neonStrong
                                glowEnabled: false
                                innerRing: false
                                borderOpacity: 0.45

                                Label {
                                    anchors.centerIn: parent
                                    text: ""
                                    color: Theme.neonStrong
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 18
                                }
                            }

                            Rectangle {
                                id: launcherSearchField
                                width: parent.width - 52
                                height: 42
                                radius: Theme.radiusMedium
                                color: Theme.background
                                border.width: 1
                                border.color: launcherSearch.activeFocus ? Theme.neonStrong : Theme.alpha(Theme.neonDark, 0.72)

                                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                                Label {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: shell.launcherMode === "apps"
                                    text: shell.launcherResults.length + " app"
                                    color: Theme.textMuted
                                    font.family: Theme.technicalFontFamily
                                    font.pixelSize: 11
                                    font.weight: 700
                                }

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 10

                                    Label {
                                        text: ""
                                        color: launcherSearch.activeFocus ? Theme.neonStrong : Theme.neonSoft
                                        anchors.verticalCenter: parent.verticalCenter
                                        font.pixelSize: 15
                                    }

                                    TextInput {
                                        id: launcherSearch
                                        width: parent.width - 100
                                        height: parent.height
                                        text: shell.launcherMode === "aur" ? shell.aurQuery : shell.launcherQuery
                                        color: Theme.textPrimary
                                        selectionColor: Theme.alpha(Theme.neon, 0.42)
                                        selectedTextColor: Theme.textPrimary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 15
                                        font.weight: 700
                                        verticalAlignment: TextInput.AlignVCenter
                                        clip: true

                                        Text {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: parent.text === "" && shell.launcherMode === "aur"
                                            text: "Cerca nell'AUR..."
                                            color: Theme.textMuted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 15
                                            enabled: false
                                        }

                                        onTextChanged: {
                                            if (shell.launcherMode === "aur") {
                                                shell.aurQuery = text
                                                shell.startAurSearch(text)
                                            } else {
                                                shell.launcherQuery = text
                                            }
                                            if (appFlick)
                                                appFlick.contentY = 0
                                        }
                                        Keys.onEscapePressed: shell.closeLauncher()
                                        Keys.onDownPressed: {
                                            if (shell.launcherMode !== "apps") return
                                            shell.launcherIndex = Math.min(shell.launcherResults.length - 1, shell.launcherIndex + 1)
                                            launcherPopup.ensureVisible()
                                        }
                                        Keys.onUpPressed: {
                                            if (shell.launcherMode !== "apps") return
                                            shell.launcherIndex = Math.max(0, shell.launcherIndex - 1)
                                            launcherPopup.ensureVisible()
                                        }
                                        Keys.onTabPressed: if (shell.launcherMode === "apps") shell.cycleCategory(1)
                                        Keys.onBacktabPressed: if (shell.launcherMode === "apps") shell.cycleCategory(-1)
                                        Keys.onReturnPressed: {
                                            if (shell.launcherMode === "aur") {
                                                shell.aurDebounceTimer.stop()
                                                shell.executeAurSearch(text)
                                            } else {
                                                var apps = shell.launcherResults
                                                var app = apps[shell.launcherIndex] || apps[0]
                                                if (app)
                                                    shell.launchApp(app.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            height: 24
                            spacing: 10

                            Text {
                                text: shell.trackText
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: 700
                                elide: Text.ElideRight
                                width: parent.width - launcherControls.width - launcherMiniViz.width - parent.spacing * 2
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Row {
                                id: launcherControls
                                spacing: 5
                                anchors.verticalCenter: parent.verticalCenter

                                MediaButton { icon: ""; command: "playerctl previous" }
                                MediaButton { icon: shell.audioPlaying ? "" : ""; command: "playerctl play-pause" }
                                MediaButton { icon: ""; command: "playerctl next" }
                            }

                            MiniVisualizer {
                                id: launcherMiniViz
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Row {
                            width: parent.width
                            height: 28
                            spacing: 6

                            Rectangle {
                                width: appsModeLabel.implicitWidth + 20
                                height: 24
                                radius: Theme.radiusSmall
                                color: shell.launcherMode === "apps" ? Theme.alpha(Theme.neon, 0.18) : appsModeMouse.containsMouse ? Theme.panelHover : "transparent"
                                border.width: shell.launcherMode === "apps" ? 1 : 0
                                border.color: Theme.alpha(Theme.neon, 0.68)
                                anchors.verticalCenter: parent.verticalCenter
                                scale: appsModeMouse.pressed ? 0.97 : appsModeMouse.containsMouse ? 1.035 : 1.0

                                Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                                Text {
                                    id: appsModeLabel
                                    anchors.centerIn: parent
                                    text: "  Applicazioni"
                                    color: shell.launcherMode === "apps" ? Theme.neonStrong : Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: shell.launcherMode === "apps" ? 800 : 700
                                }

                                MouseArea {
                                    id: appsModeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        shell.launcherMode = "apps"
                                        shell.cancelAurSearch()
                                        launcherSearch.forceActiveFocus()
                                    }
                                }
                            }

                            Rectangle {
                                width: aurModeLabel.implicitWidth + 20
                                height: 24
                                radius: Theme.radiusSmall
                                color: shell.launcherMode === "aur" ? Theme.alpha(Theme.neon, 0.18) : aurModeMouse.containsMouse ? Theme.panelHover : "transparent"
                                border.width: shell.launcherMode === "aur" ? 1 : 0
                                border.color: Theme.alpha(Theme.neon, 0.68)
                                anchors.verticalCenter: parent.verticalCenter
                                scale: aurModeMouse.pressed ? 0.97 : aurModeMouse.containsMouse ? 1.035 : 1.0

                                Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                                Text {
                                    id: aurModeLabel
                                    anchors.centerIn: parent
                                    text: "  Pacchetti AUR"
                                    color: shell.launcherMode === "aur" ? Theme.neonStrong : Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: shell.launcherMode === "aur" ? 800 : 700
                                }

                                MouseArea {
                                    id: aurModeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        shell.launcherMode = "aur"
                                        shell.aurQuery = launcherSearch.text
                                        shell.startAurSearch(launcherSearch.text)
                                        launcherSearch.forceActiveFocus()
                                    }
                                }
                            }

                            Item { width: parent.width - appsModeLabel.width - aurModeLabel.width - 60; height: 1 }

                            Rectangle {
                                width: 24
                                height: 24
                                radius: Theme.radiusSmall
                                anchors.verticalCenter: parent.verticalCenter
                                visible: shell.launcherMode === "aur"
                                color: refreshMouse.containsMouse ? Theme.panelHover : Theme.panelRaised
                                border.width: 1
                                border.color: Theme.alpha(Theme.neon, refreshMouse.containsMouse ? 0.64 : 0.30)
                                scale: refreshMouse.pressed ? 0.97 : refreshMouse.containsMouse ? 1.04 : 1.0

                                Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰑓"
                                    color: Theme.neon
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }

                                MouseArea {
                                    id: refreshMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        shell.executeAurSearch(shell.aurQuery)
                                    }
                                }
                            }
                        }

                        NeonSeparator { width: parent.width; accentColor: Theme.neon; notch: false }

                        Row {
                            width: parent.width
                            height: 352
                            spacing: 12

                            NeonPanel {
                                width: 118
                                height: parent.height
                                visible: shell.launcherMode === "apps"
                                cornerRadius: Theme.radiusMedium
                                panelColor: Theme.alpha(Theme.panelRaised, 0.86)
                                accentColor: Theme.neonDark
                                glowEnabled: false
                                innerRing: false
                                borderOpacity: 0.3

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 4

                                    Repeater {
                                        model: shell.launcherCategories()

                                        Rectangle {
                                            required property string modelData
                                            property bool selected: shell.launcherCategory === modelData
                                            property color categoryTint: shell.categoryColor(modelData)

                                            width: parent.width
                                            height: 29
                                            radius: Theme.radiusSmall
                                            color: selected ? Theme.alpha(categoryTint, 0.17) : categoryMouse.containsMouse ? Theme.panelHover : "transparent"
                                            border.width: selected ? 1 : 0
                                            border.color: Theme.alpha(categoryTint, 0.64)
                                            scale: categoryMouse.pressed ? 0.98 : categoryMouse.containsMouse ? 1.025 : 1.0

                                            Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                                            Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                            Row {
                                                anchors.fill: parent
                                                anchors.leftMargin: 9
                                                anchors.rightMargin: 8
                                                spacing: 7

                                                Text {
                                                    text: shell.categoryIcon(modelData)
                                                    color: categoryTint
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }

                                                Text {
                                                    text: modelData
                                                    width: parent.width - 42
                                                    color: selected ? Theme.textPrimary : Theme.textSecondary
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    font.weight: selected ? 800 : 700
                                                    elide: Text.ElideRight
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }

                                                Text {
                                                    text: shell.categoryCount(modelData)
                                                    color: selected ? categoryTint : Theme.textMuted
                                                    font.family: Theme.technicalFontFamily
                                                    font.pixelSize: 10
                                                    font.weight: 800
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }

                                            MouseArea {
                                                id: categoryMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    shell.launcherCategory = modelData
                                                    appFlick.contentY = 0
                                                    launcherSearch.forceActiveFocus()
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 60
                                        visible: !shell.appsLoading && shell.launcherResults.length === 0
                                        radius: Theme.radiusMedium
                                        color: Theme.panelRaised
                                        border.width: 1
                                        border.color: Theme.alpha(Theme.neonDark, 0.42)

                                        Label {
                                            anchors.centerIn: parent
                                            text: shell.launcherQuery ? "Nessuna app trovata per \"" + shell.launcherQuery + "\"" : "Nessuna applicazione in questa categoria"
                                            color: Theme.textMuted
                                            font.pixelSize: 13
                                        }
                                    }
                                }
                            }

                            Flickable {
                                id: appFlick
                                width: shell.launcherMode === "aur" ? parent.width - 8 : parent.width - 130
                                height: parent.height
                                visible: shell.launcherMode === "apps"
                                contentWidth: width
                                contentHeight: appColumn.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                flickableDirection: Flickable.VerticalFlick

                                WheelHandler {
                                    target: appFlick
                                    onWheel: function(event) {
                                        var maxY = Math.max(0, appFlick.contentHeight - appFlick.height)
                                        appFlick.contentY = Math.max(0, Math.min(maxY, appFlick.contentY - event.angleDelta.y * 0.45))
                                        event.accepted = true
                                    }
                                }

                                ScrollBar.vertical: ScrollBar {
                                    id: appScroll
                                    policy: appFlick.contentHeight > appFlick.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                                    interactive: true
                                    hoverEnabled: true
                                    width: 16          // wide hit area; the visible handle grows on hover
                                    padding: 2
                                    minimumSize: 0.08
                                    contentItem: Item {
                                        implicitWidth: 12
                                        Rectangle {
                                            anchors.right: parent.right
                                            width: appScroll.pressed ? 11 : appScroll.hovered ? 9 : 4
                                            height: parent.height
                                            radius: width / 2
                                            color: appScroll.pressed ? Theme.neonStrong : appScroll.hovered ? Theme.neon : Theme.alpha(Theme.neon, 0.58)
                                            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                        }
                                    }
                                    background: Item {
                                        Rectangle {
                                            anchors.right: parent.right
                                            width: appScroll.hovered || appScroll.pressed ? 11 : 4
                                            height: parent.height
                                            radius: width / 2
                                            color: Theme.alpha(Theme.neonDark, appScroll.hovered ? 0.34 : 0.16)
                                            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                        }
                                    }
                                }

                                Column {
                                    id: appColumn
                                    width: appFlick.width - 8
                                    spacing: 8

                                    NeonPanel {
                                        width: parent.width
                                        height: 60
                                        visible: shell.appsLoading
                                        cornerRadius: Theme.radiusMedium
                                        panelColor: Theme.panelRaised
                                        accentColor: Theme.neonDark
                                        glowEnabled: false

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 10

                                            Rectangle {
                                                width: 24
                                                height: 24
                                                radius: 12
                                                border.width: 3
                                                border.color: Theme.alpha(Theme.neon, 0.64)
                                                color: "transparent"
                                                RotationAnimation on rotation { from: 0; to: 360; duration: 1000; running: shell.appsLoading; loops: Animation.Infinite }

                                                Rectangle {
                                                    anchors.fill: parent
                                                    anchors.margins: 3
                                                    radius: 9
                                                    color: Theme.alpha(Theme.neonStrong, 0.24)
                                                }
                                            }

                                            Label {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "Caricamento applicazioni..."
                                                color: Theme.textSecondary
                                                font.pixelSize: 13
                                            }
                                        }
                                    }

                                    Repeater {
                                        model: shell.launcherResults

                                        NeonPanel {
                                            required property var modelData
                                            required property int index
                                            property bool current: shell.launcherIndex === index
                                            width: parent.width
                                            height: 44
                                            cornerRadius: Theme.radiusMedium
                                            panelColor: current ? Theme.alpha(Theme.neon, 0.13) : launcherAppMouse.containsMouse ? Theme.panelHover : Theme.panelRaised
                                            accentColor: current ? Theme.neonStrong : Theme.neonDark
                                            glowEnabled: false
                                            innerRing: false
                                            borderOpacity: current ? 0.85 : 0.28
                                            scale: launcherAppMouse.pressed ? 0.98 : current ? 1.012 : 1.0

                                            Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                                            Behavior on panelColor { ColorAnimation { duration: Theme.animFast } }

                                            Row {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: 10

                                                Rectangle {
                                                    width: 30
                                                    height: 30
                                                    radius: 9
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    color: Theme.alpha(shell.categoryColor(modelData.category), 0.22)
                                                    border.width: 1
                                                    border.color: Theme.alpha(shell.categoryColor(modelData.category), 0.48)

                                                    IconImage {
                                                        id: applicationIcon
                                                        anchors.centerIn: parent
                                                        width: 22
                                                        height: 22
                                                        source: shell.resolveIconSource(modelData.icon)
                                                        asynchronous: true
                                                        visible: String(source) !== "" && status !== Image.Error
                                                    }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        visible: String(applicationIcon.source) === "" || applicationIcon.status === Image.Error
                                                        text: modelData.name.length > 0 ? modelData.name[0].toUpperCase() : "?"
                                                        color: Theme.textPrimary
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 11
                                                        font.weight: 800
                                                    }
                                                }

                                                Label {
                                                    width: parent.width - categoryChip.width - 54
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    font.weight: current ? 700 : 500
                                                    text: modelData.name
                                                    color: Theme.textPrimary
                                                    elide: Text.ElideRight
                                                }

                                                Rectangle {
                                                    id: categoryChip
                                                    width: Math.max(54, categoryLabel.implicitWidth + 18)
                                                    height: 22
                                                    radius: Theme.radiusSmall
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    color: Theme.alpha(categoryTint, launcherAppMouse.containsMouse ? 0.24 : 0.14)
                                                    border.width: 1
                                                    border.color: Theme.alpha(categoryTint, launcherAppMouse.containsMouse ? 0.58 : 0.36)

                                                    property color categoryTint: shell.categoryColor(modelData.category)

                                                    Text {
                                                        id: categoryLabel
                                                        anchors.centerIn: parent
                                                        text: modelData.category
                                                        color: categoryChip.categoryTint
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        font.weight: 800
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                width: 3
                                                height: parent.height - 16
                                                radius: 2
                                                anchors.left: parent.left
                                                anchors.leftMargin: 4
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: Theme.neonStrong
                                                opacity: current ? 1 : 0
                                                Behavior on opacity { NumberAnimation { duration: 140 } }
                                            }

                                            MouseArea {
                                                id: launcherAppMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onEntered: shell.launcherIndex = index
                                                onClicked: shell.launchApp(modelData.id)
                                            }
                                        }
                                    }
                                }
                            }

                            AurPackagePage {
                                width: shell.launcherMode === "aur" ? parent.width - 8 : 0
                                height: parent.height
                                visible: shell.launcherMode === "aur"
                                results: shell.aurResults
                                searching: shell.aurSearching
                                error: shell.aurError
                                query: shell.aurQuery
                                hasSearched: shell.aurQuery.length >= 2 || shell.aurResults.length > 0 || shell.aurError !== ""
                                onInstallRequested: function(packageName) {
                                    shell.openAurTerminal(["kitty", "--title", "Paru — Installa " + packageName, "paru", "-S", packageName])
                                }
                                onRemoveRequested: function(packageName) {
                                    shell.openAurTerminal(["kitty", "--title", "Paru — Rimuovi " + packageName, "paru", "-Rns", packageName])
                                }
                                onRefreshRequested: {
                                    shell.executeAurSearch(shell.aurQuery)
                                }
                            }
                        }

                        NeonSeparator { width: parent.width; accentColor: Theme.neonDark; notch: false }

                        Row {
                            width: parent.width
                            height: 26
                            spacing: 6

                            Text {
                                width: parent.width - powerButtons.width - parent.spacing
                                anchors.verticalCenter: parent.verticalCenter
                                text: shell.launcherHint !== "" ? shell.launcherHint : "\u2191\u2193 naviga   \u21B5 apri   Tab categoria   Esc chiudi"
                                color: shell.launcherHint !== "" ? Theme.neonStrong : Theme.textMuted
                                font.family: Theme.technicalFontFamily
                                font.pixelSize: 11
                                font.weight: 700
                                elide: Text.ElideRight
                            }

                            Row {
                                id: powerButtons
                                spacing: 4
                                anchors.verticalCenter: parent.verticalCenter

                                PowerButton { icon: "\uf023"; tip: "Blocca schermo"; cmd: "loginctl lock-session"; onHint: function(s) { shell.launcherHint = s }; onRun: function(c) { shell.closeLauncher(); shell.run(c) } }
                                PowerButton { icon: "\uf08b"; tip: "Esci dalla sessione"; cmd: "hyprctl dispatch exit"; danger: true; onHint: function(s) { shell.launcherHint = s }; onRun: function(c) { shell.closeLauncher(); shell.run(c) } }
                                PowerButton { icon: "\uf021"; tip: "Riavvia"; cmd: "systemctl reboot"; danger: true; onHint: function(s) { shell.launcherHint = s }; onRun: function(c) { shell.closeLauncher(); shell.run(c) } }
                                PowerButton { icon: "\uf011"; tip: "Spegni"; cmd: "systemctl poweroff"; danger: true; onHint: function(s) { shell.launcherHint = s }; onRun: function(c) { shell.closeLauncher(); shell.run(c) } }
                            }
                        }
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            readonly property string monitorName: I3.monitorFor(modelData) ? I3.monitorFor(modelData).name : modelData.name
            readonly property real uiScale: Theme.scaleForMonitor(monitorName)

            screen: modelData
            visible: shell.calendarOpen && shell.calendarMonitorName === monitorName
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            color: "transparent"
            mask: Region { width: 0; height: 0 }
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell-popup"
            WlrLayershell.exclusiveZone: 0
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                visible: shell.calendarOpen && shell.calendarMonitorName === parent.monitorName
                x: Math.round(parent.width - width - 6)
                y: 52 * parent.uiScale
                width: 520 * parent.uiScale
                height: 470 * parent.uiScale
                radius: Theme.radiusLarge * parent.uiScale
                color: Theme.alpha(Theme.neon, 0.04)
                border.width: 1
                border.color: Theme.alpha(Theme.neon, 0.10)
            }
        }
    }
}
