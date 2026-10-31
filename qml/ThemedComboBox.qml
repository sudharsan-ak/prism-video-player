import QtQuick
import QtQuick.Controls

// Default QtQuick.Controls ComboBox ignores the app's theme colors
// entirely (white text on white background in the dropdown popup) -
// this wraps it with explicit background/contentItem/popup/delegate
// styling so it actually reads against every theme, light or dark.
ComboBox {
    id: control
    property var tokens: ({})

    delegate: ItemDelegate {
        width: control.width
        highlighted: control.highlightedIndex === index
        contentItem: Text {
            text: modelData
            color: control.tokens.textPrimary || "#000"
            font.pixelSize: 11
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            color: highlighted ? (control.tokens.accentTint || "#20808080") : (control.tokens.panelGlassStrong || "#fff")
        }
    }

    indicator: Text {
        x: control.width - width - 10
        y: control.topPadding + (control.availableHeight - height) / 2
        text: "▾"
        font.pixelSize: 10
        color: control.tokens.textSecondary || "#888"
    }

    contentItem: Text {
        leftPadding: 10
        rightPadding: control.indicator.width + 10
        text: control.displayText
        font.pixelSize: 11
        color: control.tokens.textPrimary || "#000"
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        implicitHeight: 32
        radius: 7
        color: control.tokens.panelGlassStrong || "#fff"
        border.color: control.tokens.panelBorder || "#ccc"
        border.width: 1
    }

    popup: Popup {
        y: control.height + 2
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight, 220)
        padding: 1

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }

        background: Rectangle {
            radius: 7
            color: control.tokens.panelGlassStrong || "#fff"
            border.color: control.tokens.panelBorder || "#ccc"
            border.width: 1
        }
    }
}
