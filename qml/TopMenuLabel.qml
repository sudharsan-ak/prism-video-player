import QtQuick
import QtQuick.Controls

// One top-bar text menu label (File, Play, Video, ...). Fixed height
// and centered text on the chip so the active state never shifts the
// label's baseline - this was flagged explicitly as a hard acceptance
// criterion after the design mockup showed a 1px misalignment
// (PHASE1_PLAN_QT.md section 6.2).
//
// Named TopMenuLabel, not MenuBarItem: Qt Quick Controls ships its own
// built-in MenuBarItem type (qml/QtQuick/Controls/<style>/MenuBarItem.qml
// in every style), and naming this component MenuBarItem let Qt's
// internal type silently shadow this one the moment a sibling Menu
// existed in the same file, breaking custom signal resolution with a
// "Type TopBar unavailable" / "non-existent property" error that had
// nothing to do with the actual binding. Never reuse a Qt Quick
// Controls type name for a local component.
Item {
    id: root
    width: label.implicitWidth + 16
    height: 26

    property string text: ""
    property Menu menu: null
    property var tokens: null

    signal menuToggleRequested()

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: (root.menu && root.menu.visible && root.tokens) ? (root.tokens.panelGlassStrong || "#fff") : "transparent"
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        font.pixelSize: 11
        font.weight: (root.menu && root.menu.visible) ? Font.DemiBold : Font.Normal
        color: (root.menu && root.menu.visible && root.tokens)
            ? (root.tokens.accentSolid || root.tokens.textPrimary)
            : (root.tokens ? (root.tokens.textSecondary || "#888") : "#888")
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.menuToggleRequested()
    }
}
