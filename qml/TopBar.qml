import QtQuick
import QtQuick.Controls
import QtQuick.Window

// Single-row top bar (PHASE1_PLAN_QT.md section 6.2): logo, File/Play/
// Video/Audio/Subtitle/Tools/Settings text menus, Library + Adjustments
// toggle buttons, centered now-playing title, window controls.
Rectangle {
    id: root
    height: 42
    color: tokens.panelGlass || "#fff"
    border.color: tokens.panelBorder || "transparent"
    border.width: 1

    property var tokens: themeController.tokens
    property var mpv: null
    property bool libraryOpen: false
    property bool adjustmentsOpen: false

    signal libraryToggled()
    signal adjustmentsToggled()
    signal openFilesRequested()
    signal addFolderRequested()
    signal loadSubtitleRequested()

    // Native title bar is disabled (frameless window), so this bar must
    // provide its own drag-to-move. Sits below every other child so
    // menu buttons and window controls still receive their own clicks.
    MouseArea {
        anchors.fill: parent
        onPressed: function(mouse) {
            if (mouse.button === Qt.LeftButton)
                root.Window.window.startSystemMove();
        }
        onDoubleClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                root.Window.window.visibility === Window.Maximized
                    ? root.Window.window.showNormal()
                    : root.Window.window.showMaximized();
            }
        }
    }

    Text {
        anchors.centerIn: parent
        // Constrained so a long filename elides instead of overlapping
        // the menu row or window controls on a narrow window - this is
        // what caused the title to overlap "Adjustments" before that
        // button was moved into the bottom control bar.
        width: Math.max(0, Math.min(implicitWidth, root.width - 2 * (leftRow.width + 180)))
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: mpv && mpv.mediaTitle ? mpv.mediaTitle : (mpv && mpv.mediaPath ? mpv.mediaPath.split(/[\\\/]/).pop() : "")
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: root.tokens.textPrimary || "#000"
    }

    Row {
        id: leftRow
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 14
        spacing: 15

        // Real app icon only, no wordmark - the taskbar/window icon
        // already identifies the app, so a repeated "Prism" text label
        // here was pure redundancy eating width the title needed more.
        Image {
            // Transparent-background cutout of just the prism shape,
            // not the square taskbar .ico - the .ico's solid dark
            // square background read as a boxy chip against the top
            // bar's own background.
            source: "qrc:/qt/qml/Prism/resources/icon_topbar.png"
            width: 22
            height: 18
            anchors.verticalCenter: parent.verticalCenter
            smooth: true
            fillMode: Image.PreserveAspectFit
        }

        Rectangle { width: 1; height: 14; color: root.tokens.panelBorder || "#ccc"; anchors.verticalCenter: parent.verticalCenter }

        TopMenuLabel {
            id: fileItem
            text: "File"
            tokens: root.tokens
            menu: fileMenu
            onMenuToggleRequested: fileMenu.visible ? fileMenu.close() : fileMenu.open()
        }
        // Play/Video/Audio/Subtitle grouped under one "Playback" entry,
        // Tools/Settings under "Tools" - 7 top-level items (plus Library)
        // left too little room for the now-playing title at normal
        // window widths.
        TopMenuLabel {
            id: playbackItem
            text: "Playback"
            tokens: root.tokens
            menu: playbackMenu
            onMenuToggleRequested: playbackMenu.visible ? playbackMenu.close() : playbackMenu.open()
        }
        Rectangle {
            id: editEntry
            height: 26
            width: editLabel.implicitWidth + 16
            radius: 6
            anchors.verticalCenter: parent.verticalCenter
            color: root.editorActive ? (root.tokens.accentTint || "#333") : "transparent"
            Text {
                id: editLabel
                anchors.centerIn: parent
                text: "Edit"
                color: root.editorActive
                    ? (root.tokens.accentSolid || "#A89BFF")
                    : (root.tokens.textSecondary || "#888")
                font.pixelSize: 11
                font.weight: root.editorActive ? Font.DemiBold : Font.Normal
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.editRequested()
            }
        }
        TopMenuLabel {
            id: moreItem
            text: "Tools"
            tokens: root.tokens
            menu: moreMenu
            onMenuToggleRequested: moreMenu.visible ? moreMenu.close() : moreMenu.open()
        }

        Rectangle {
            width: libraryLabel.implicitWidth + 32
            height: 24
            radius: 8
            anchors.verticalCenter: parent.verticalCenter
            color: root.libraryOpen ? (root.tokens.accentTint || "transparent") : "transparent"
            border.color: root.libraryOpen ? (root.tokens.accentSolid || "transparent") : (root.tokens.panelBorder || "#ccc")
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: 6
                Text { text: "☰"; font.pixelSize: 11; color: root.libraryOpen ? (root.tokens.accentSolid || "#000") : (root.tokens.textSecondary || "#888") }
                Text {
                    id: libraryLabel
                    text: "Library"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    color: root.libraryOpen ? (root.tokens.accentSolid || "#000") : (root.tokens.textSecondary || "#888")
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.libraryToggled() }
        }

    }

    // Standard Windows title-bar sizing: ~46px-wide click zones (not a
    // bare Text glyph with no padding, which is what made these read as
    // cramped), hover feedback, and close turns red on hover like every
    // native Windows app.
    component WindowControlButton: Item {
        id: winBtn
        property string glyph: ""
        property bool isClose: false
        signal clicked()

        // No anchors here: a Row positions its children itself, and an
        // anchored child fights that positioning - this is what made
        // the middle (maximize) button's actual clickable rect drift
        // from where it visually sat, so hovering it did nothing while
        // its neighbors worked fine.
        width: 46
        height: root.height

        Rectangle {
            anchors.fill: parent
            color: hoverArea.containsMouse
                ? (winBtn.isClose ? "#E81123" : (root.tokens.panelBorder || "#00000014"))
                : "transparent"
        }
        Text {
            visible: winBtn.glyph !== ""
            anchors.centerIn: parent
            text: winBtn.glyph
            font.pixelSize: 11
            color: hoverArea.containsMouse && winBtn.isClose ? "white" : (root.tokens.textMuted || "#888")
        }
        // Drawn, not a font glyph: the maximize/restore pair needs two
        // precise overlapping-square shapes that must swap reliably
        // based on window state, which a static "□" text glyph can
        // neither draw correctly nor update (it was hardcoded, so it
        // never reflected whether the window was actually maximized).
        Item {
            visible: winBtn.glyph === ""
            anchors.centerIn: parent
            width: 10
            height: 10

            // Maximize icon: single square outline.
            Rectangle {
                visible: prismWindow.visibility !== Window.Maximized
                anchors.fill: parent
                color: "transparent"
                border.color: hoverArea.containsMouse ? (root.tokens.textPrimary || "#000") : (root.tokens.textMuted || "#888")
                border.width: 1
            }

            // Restore icon: two overlapping square outlines.
            Item {
                visible: prismWindow.visibility === Window.Maximized
                anchors.fill: parent
                Rectangle {
                    width: 8; height: 8
                    anchors.top: parent.top
                    anchors.right: parent.right
                    color: "transparent"
                    border.color: hoverArea.containsMouse ? (root.tokens.textPrimary || "#000") : (root.tokens.textMuted || "#888")
                    border.width: 1
                }
                Rectangle {
                    width: 8; height: 8
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    color: root.tokens.panelGlass || "#fff"
                    border.color: hoverArea.containsMouse ? (root.tokens.textPrimary || "#000") : (root.tokens.textMuted || "#888")
                    border.width: 1
                }
            }
        }
        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: winBtn.clicked()
        }
    }

    Row {
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        WindowControlButton { glyph: "−"; onClicked: prismWindow.showMinimized() }
        WindowControlButton {
            // Empty glyph routes to the drawn maximize/restore icon above.
            glyph: ""
            onClicked: prismWindow.visibility === Window.Maximized ? prismWindow.showNormal() : prismWindow.showMaximized()
        }
        WindowControlButton { glyph: "✕"; isClose: true; onClicked: Qt.quit() }
    }

    // Each Menu is parented to its own TopMenuLabel button, not to the
    // bar itself, so x/y are plain local coordinates (0, button height)
    // instead of a screen-mapped guess - this is what actually anchors
    // the dropdown directly under its button (PHASE1_PLAN_QT.md section
    // 6.3). Parenting to root made every menu open at (0,0) regardless
    // of which button was clicked.
    FileMenu {
        id: fileMenu
        parent: fileItem
        x: 0
        y: fileItem.height
        onOpenFilesRequested: root.openFilesRequested()
        onAddFolderRequested: root.addFolderRequested()
    }
    PlaybackMenu {
        id: playbackMenu
        parent: playbackItem
        x: 0
        y: playbackItem.height
        mpv: root.mpv
        onLoadSubtitleRequested: root.loadSubtitleRequested()
    }
    MoreMenu {
        id: moreMenu
        parent: moreItem
        x: 0
        y: moreItem.height
        mpv: root.mpv
    }
}
