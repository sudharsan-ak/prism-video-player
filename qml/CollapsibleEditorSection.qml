import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A collapsible, theme-aware sidebar group. Children are laid out in a
// ColumnLayout and stay instantiated when hidden, preserving their state.
ColumnLayout {
    id: root
    default property alias sectionContent: sectionBody.data
    property var tokens: themeController.tokens
    property string titleText: ""
    property string subtitleText: ""
    property bool expanded: false
    spacing: 0
    Layout.fillWidth: true

    Button {
        id: headerButton
        Layout.fillWidth: true
        Layout.preferredHeight: 43
        padding: 0
        onClicked: root.expanded = !root.expanded
        ToolTip.visible: hovered
        ToolTip.text: root.expanded ? "Collapse " + root.titleText
                                    : "Expand " + root.titleText
        background: Rectangle {
            radius: 8
            color: headerButton.down || headerButton.hovered
                ? (root.tokens.accentTint || "#21342C") : "transparent"
            border.width: headerButton.activeFocus ? 1 : 0
            border.color: root.tokens.accentSolid || "#36DA84"
        }
        contentItem: RowLayout {
            spacing: 8
            Text {
                text: root.titleText
                font.pixelSize: 11
                font.bold: true
                color: root.tokens.textPrimary || "#FFFFFF"
            }
            Item { Layout.fillWidth: true }
            Text {
                visible: root.subtitleText.length > 0
                text: root.subtitleText
                font.pixelSize: 10
                color: root.tokens.textSecondary || "#AAA"
                elide: Text.ElideRight
                Layout.maximumWidth: 135
            }
            Text {
                text: root.expanded ? "▾" : "▸"
                font.pixelSize: 14
                color: root.tokens.accentSolid || "#36DA84"
                Layout.preferredWidth: 16
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    ColumnLayout {
        id: sectionBody
        Layout.fillWidth: true
        visible: root.expanded
        spacing: 8
        // Child controls keep their bindings and state while collapsed.
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: root.tokens.panelBorder || "#444"
        opacity: 0.65
    }
}
