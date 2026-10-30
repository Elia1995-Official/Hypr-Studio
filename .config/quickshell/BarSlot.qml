import QtQuick

// One slot of the bar: a built-in module (looked up in `components`) or a user-defined CustomModule.
Loader {
    id: slot
    property var cfg: ({})
    property var components: ({})
    property var visibility: ({})
    property var host: null

    readonly property bool builtin: cfg && components && components[cfg.type] !== undefined
    visible: cfg && cfg.hidden !== true && (visibility[cfg.type] === undefined || visibility[cfg.type])
    sourceComponent: builtin ? components[cfg.type] : custom

    Component {
        id: custom
        CustomModule { cfg: slot.cfg; host: slot.host }
    }
}
