import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Functional trim, crop and rotation controls share the existing export dock.
Rectangle {
    id: root
    width: 288
    color: tokens.panelGlass || "#20202B"
    border.color: tokens.panelBorder || "#444"
    border.width: 1

    property var tokens: themeController.tokens
    onVisibleChanged: {
        if (!visible)
            exportModePopup.close();
    }
    property string sourceTitle: ""
    property string sourcePath: ""
    readonly property bool canReplace: sourcePath.toLowerCase().endsWith(".mp4") && !segmented
    property bool segmented: false
    property real editedDuration: 0
    property int segmentCount: 1
    property var segmentItems: []
    property int selectedSegmentId: -1
    property real startTime: 0
    property real endTime: 0
    property real duration: 0
    property real editSpeed: 1.0
    property int audioVolumePercent: 100
    property bool cropActive: false
    property real cropX: 0
    property real cropY: 0
    property real cropWidth: 1
    property real cropHeight: 1
    property int quarterTurns: 0
    readonly property bool isCropped: cropX > 0.0001 || cropY > 0.0001 ||
        cropWidth < 0.9999 || cropHeight < 0.9999
    readonly property var presetIds: ["ultrafast", "veryfast", "fast", "medium", "slow"]
    function presetLabel(id) {
        const names = ["Ultrafast", "Very Fast", "Fast", "Medium", "Slow"];
        return names[Math.max(0, presetIds.indexOf(id))];
    }
    function gifLabel(id) {
        return id === "high" ? "High Quality (640px · 12fps)" :
               id === "compact" ? "Compact (360px · 8fps)" :
                                  "Balanced (480px · 10fps)";
    }

    signal closeRequested()
    signal exportRequested()
    signal exportGifRequested()
    signal replaceModeRequested()
     signal previewRequested()
    signal resetRequested()
    signal queueRequested()
    signal cropModeToggled()
    signal cropResetRequested()
    signal cropPresetRequested(string preset)
    signal rotationRequested(int quarterTurns)
    signal selectSegmentRequested(int id)
    signal restoreSegmentRequested(int id)

    function mp4ModeLabel() {
        if (segmented && settingsStore.mp4ExportMode === "replace")
            return "Copy only (segmented edit)";
        switch (settingsStore.mp4ExportMode) {
        case "saveAs": return "Save As dialog";
        case "replace": return "Replace original";
        default: return "Quick copy";
        }
    }
    function gifModeLabel() {
        return settingsStore.gifExportMode === "saveAs" ? "Save As dialog" : "Quick GIF";
    }

    component ModeChoice: Button {
        id: choice
        property string detail: ""
        property bool selected: false
        Layout.fillWidth: true
        Layout.preferredHeight: 43
        padding: 7
        font.pixelSize: 11
        background: Rectangle {
            radius: 7
            color: choice.selected ? (root.tokens.accentTint || "#183424")
                                   : (choice.hovered ? (root.tokens.panelGlass || "#181D19") : "transparent")
            border.width: choice.selected ? 1 : 0
            border.color: root.tokens.accentSolid || "#2BFA83"
        }
        contentItem: RowLayout {
            spacing: 9
            Rectangle {
                Layout.preferredWidth: 12
                Layout.preferredHeight: 12
                radius: 6
                color: choice.selected ? (root.tokens.accentSolid || "#2BFA83") : "transparent"
                border.width: 1
                border.color: choice.selected
                    ? (root.tokens.accentSolid || "#2BFA83")
                    : (root.tokens.textMuted || "#777")
                Rectangle {
                    anchors.centerIn: parent
                    width: 4
                    height: 4
                    radius: 2
                    color: root.tokens.videoCardBackground || "#08130B"
                    visible: choice.selected
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: choice.text
                    color: root.tokens.textPrimary || "white"
                    font.pixelSize: 11
                    font.bold: choice.selected
                }
                Text {
                    Layout.fillWidth: true
                    text: choice.detail
                    color: root.tokens.textSecondary || "#AAA"
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }
            }
        }
    }

    function showExportModePopup() {
        const overlay = exportModePopup.parent;
        const pt = settingsButton.mapToItem(overlay, 0, 0);
        exportModePopup.x = Math.max(8, Math.min(pt.x + settingsButton.width - exportModePopup.width,
                                               prismWindow.width - exportModePopup.width - 8));
        const below = pt.y + settingsButton.height + 6;
        const above = pt.y - exportModePopup.height - 8;
        // The gear is pinned to the bottom; keep its menu above it
        // rather than covering the dock or extending off-screen.
        exportModePopup.y = below + exportModePopup.height <= prismWindow.height - 8
            ? below : Math.max(8, above);
        exportModePopup.open();
    }

    function timeText(seconds) {
        let s = Math.max(0, Math.floor(seconds || 0));
        let h = Math.floor(s / 3600);
        let m = Math.floor((s % 3600) / 60);
        let sec = s % 60;
        const pad = n => String(n).padStart(2, "0");
        const base = h ? h + ":" + pad(m) + ":" + pad(sec) : m + ":" + pad(sec);
        return seconds >= 0 && seconds < 10
            ? base + "." + pad(Math.floor((seconds - Math.floor(seconds)) * 100 + 0.001))
            : base;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // The header and export dock never scroll.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 47
            Layout.leftMargin: 15
            Layout.rightMargin: 9
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: "EDIT VIDEO"
                color: root.tokens.textPrimary || "white"
                font.pixelSize: 13
                font.bold: true
            }
            Button {
                id: closeEditorButton
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                text: "✕"
                enabled: exportQueue.canQueue
                onClicked: root.closeRequested()
                background: Rectangle {
                    radius: 6
                    color: closeEditorButton.hovered
                        ? (root.tokens.accentTint || "#254233") : "transparent"
                }
                contentItem: Text {
                    text: closeEditorButton.text
                    color: root.tokens.textPrimary || "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                ToolTip.visible: hovered
                ToolTip.text: "Return to player"
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 15
            Layout.rightMargin: 15
            Layout.bottomMargin: 9
            text: root.sourceTitle
            elide: Text.ElideMiddle
            color: root.tokens.textSecondary || "#aaa"
            font.pixelSize: 10
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: root.tokens.panelBorder || "#444"
        }

        // Only edit details scroll. Each group can be collapsed without
        // resetting selected crop/rotation, encoding settings or queue jobs.
        ScrollView {
            id: editScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: editScroll.availableWidth
                spacing: 2

                CollapsibleEditorSection {
                    Layout.leftMargin: 9
                    Layout.rightMargin: 9
                    tokens: root.tokens
                    titleText: "Trim"
                    subtitleText: root.timeText(root.endTime - root.startTime) + " selected"
                    expanded: false
                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        Layout.bottomMargin: 6
                        text: "Set IN and OUT points or drag the selected range in the timeline below."
                        wrapMode: Text.WordWrap
                        color: root.tokens.textSecondary || "#AAA"
                        font.pixelSize: 11
                    }
                }

                CollapsibleEditorSection {
                    Layout.leftMargin: 9
                    Layout.rightMargin: 9
                    tokens: root.tokens
                    titleText: "Crop"
                    subtitleText: root.isCropped
                        ? Math.round(root.cropWidth * 100) + "% × " +
                          Math.round(root.cropHeight * 100) + "%" : "Full frame"
                    expanded: true

                    CropControls {
                        Layout.fillWidth: true
                        Layout.leftMargin: 7
                        Layout.rightMargin: 7
                        Layout.bottomMargin: 8
                        tokens: root.tokens
                        cropActive: root.cropActive
                        cropX: root.cropX
                        cropY: root.cropY
                        cropWidth: root.cropWidth
                        cropHeight: root.cropHeight
                        quarterTurns: root.quarterTurns
                        onCropModeToggled: root.cropModeToggled()
                        onCropResetRequested: root.cropResetRequested()
                        onCropPresetRequested: function(preset) { root.cropPresetRequested(preset); }
                    }
                }

                CollapsibleEditorSection {
                    Layout.leftMargin: 9
                    Layout.rightMargin: 9
                    tokens: root.tokens
                    titleText: "Rotate"
                    subtitleText: root.quarterTurns * 90 + "°"
                    expanded: false
                    RotateControls {
                        Layout.fillWidth: true
                        Layout.leftMargin: 7
                        Layout.rightMargin: 7
                        Layout.bottomMargin: 8
                        tokens: root.tokens
                        quarterTurns: root.quarterTurns
                        onRotationRequested: function(turns) { root.rotationRequested(turns); }
                    }
                }

                CollapsibleEditorSection {
                    Layout.leftMargin: 9
                    Layout.rightMargin: 9
                    tokens: root.tokens
                    titleText: "Segments"
                    subtitleText: root.segmentItems.length + " pieces"
                    expanded: false
                    Repeater {
                        model: root.segmentItems
                        RowLayout {
                            id: segLine
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8
                            spacing: 5
                            Button {
                                Layout.fillWidth: true
                                text: "Segment " + (index + 1) +
                                      (segLine.modelData.removed ? " · Removed" : " · Kept")
                                font.pixelSize: 10
                                onClicked: root.selectSegmentRequested(segLine.modelData.id)
                                background: Rectangle {
                                    radius: 5
                                    color: root.selectedSegmentId === segLine.modelData.id
                                        ? (root.tokens.accentTint || "#193F37")
                                        : (root.tokens.panelGlassStrong || "#192B30")
                                    border.color: root.selectedSegmentId === segLine.modelData.id
                                        ? (root.tokens.accentSolid || "#28DCA7")
                                        : (root.tokens.panelBorder || "#444")
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: root.tokens.textPrimary || "#fff"
                                    font: parent.font
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                            Button {
                                text: "Restore"
                                visible: segLine.modelData.removed
                                font.pixelSize: 10
                                onClicked: root.restoreSegmentRequested(segLine.modelData.id)
                            }
                        }
                    }
                }

                CollapsibleEditorSection {
                    Layout.leftMargin: 9
                    Layout.rightMargin: 9
                    tokens: root.tokens
                    titleText: "Export Summary"
                    subtitleText: root.timeText(
                        root.editedDuration / Math.max(0.25, root.editSpeed))
                    expanded: false
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                color: root.tokens.textSecondary || "#aaa"
                font.pixelSize: 11
                text: "Output: MP4 (H.264 + AAC)\n"
                    + "Edited duration: " + root.timeText(root.editedDuration
                        / Math.max(0.25, root.editSpeed)) + "\n"
                    + "Kept segments: " + root.segmentCount + "\n"
                    + "MP4 audio: " + (root.audioVolumePercent === 0 ? "Removed" :
                       root.audioVolumePercent === 100 ? "Original level" :
                       root.audioVolumePercent + "% of original") + "\n"
                    + "GIF: " + root.gifLabel(settingsStore.gifQualityPreset)
                    + "\nRotation: " + (root.quarterTurns * 90) + "°"
                    + "\nCrop: " + (root.isCropped
                        ? Math.round(root.cropWidth * 100) + "% × " +
                          Math.round(root.cropHeight * 100) + "%"
                        : "Full frame")
                    + "\nSubtitles not included"
                lineHeight: 1.45
                wrapMode: Text.WordWrap
            }


                }

                CollapsibleEditorSection {
                    Layout.leftMargin: 9
                    Layout.rightMargin: 9
                    tokens: root.tokens
                    titleText: "Export Settings"
                    subtitleText: root.presetLabel(settingsStore.encodingPreset)
                    expanded: false
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                text: "ENCODING PRESET"
                font.pixelSize: 10
                font.bold: true
                color: root.tokens.textMuted || "#999"
            }
            Button {
                id: presetButton
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                enabled: exportQueue.canQueue
                text: root.presetLabel(settingsStore.encodingPreset) + " ▾"
                onClicked: presetMenu.open()
                background: Rectangle {
                    color: root.tokens.panelGlassStrong || "#242331"
                    radius: 8
                    border.color: root.tokens.panelBorder || "#444"
                }
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: root.tokens.textPrimary || "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                Menu {
                    id: presetMenu
                    parent: presetButton
                    y: presetButton.height
                    Repeater {
                        model: root.presetIds
                        MenuItem {
                            text: root.presetLabel(modelData)
                            checkable: true
                            checked: settingsStore.encodingPreset === modelData
                            onTriggered: settingsStore.encodingPreset = modelData
                        }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                text: "Very Fast is recommended. Slower presets may produce smaller files."
                color: root.tokens.textMuted || "#888"
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                text: "GIF QUALITY"
                font.pixelSize: 10
                font.bold: true
                color: root.tokens.textMuted || "#999"
            }
            Button {
                id: gifPresetButton
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                enabled: exportQueue.canQueue
                text: root.gifLabel(settingsStore.gifQualityPreset) + " ▾"
                onClicked: gifPresetMenu.open()
                background: Rectangle {
                    radius: 8
                    color: root.tokens.panelGlassStrong || "#242331"
                    border.color: root.tokens.panelBorder || "#444"
                }
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: root.tokens.textPrimary || "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                Menu {
                    id: gifPresetMenu
                    parent: gifPresetButton
                    y: gifPresetButton.height
                    Repeater {
                        model: ["high", "balanced", "compact"]
                        MenuItem {
                            text: root.gifLabel(modelData)
                            checkable: true
                            checked: settingsStore.gifQualityPreset === modelData
                            onTriggered: settingsStore.gifQualityPreset = modelData
                        }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                text: "Balanced is recommended. GIFs have no sound and can be much larger than MP4."
                color: root.tokens.textMuted || "#888"
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }


                }

                CollapsibleEditorSection {
                    Layout.leftMargin: 9
                    Layout.rightMargin: 9
                    tokens: root.tokens
                    titleText: "Export Queue"
                    subtitleText: exportQueue.waitingCount + " waiting"
                    expanded: false
            ExportQueuePanel {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.preferredHeight: Math.min(310, Math.max(130,
                    65 + Math.min(exportQueue.jobs.length, 3) * 80))
                visible: exportQueue.jobs.length > 0
                compact: true
            }
            Button {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                text: "View export queue"
                onClicked: root.queueRequested()
                font.pixelSize: 11
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: root.tokens.accentSolid || "#A89BFF"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 7
                    color: root.tokens.panelGlassStrong || "#242331"
                    border.color: root.tokens.panelBorder || "#444"
                }
            }


                }
                Item { Layout.preferredHeight: 10 }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: root.tokens.panelBorder || "#444"
        }

        // Permanently visible export actions, outside editScroll.
        ColumnLayout {
            id: stickyExportDock
            Layout.fillWidth: true
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 15
                Layout.rightMargin: 15
                Layout.topMargin: 11
                Text {
                    Layout.fillWidth: true
                    text: "QUICK EXPORT"
                    font.pixelSize: 10
                    font.bold: true
                    color: root.tokens.textMuted || "#999"
                }
                Button {
                    id: queueShortcut
                    text: "Queue (" + exportQueue.jobs.length + ")"
                    font.pixelSize: 10
                    flat: true
                    onClicked: root.queueRequested()
                    background: Rectangle {
                        radius: 6
                        color: queueShortcut.hovered
                            ? (root.tokens.accentTint || "#203A29") : "transparent"
                    }
                    contentItem: Text {
                        text: queueShortcut.text
                        color: root.tokens.accentSolid || "#2BFA83"
                        font: queueShortcut.font
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    ToolTip.visible: hovered
                    ToolTip.text: "Open export queue"
                }
            }

            Rectangle {
                id: minimalDock
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.preferredHeight: 48
                color: root.tokens.panelGlassStrong || "#111A13"
                border.color: root.tokens.panelBorder || "#375443"
                border.width: 1
                radius: 10

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 5
                    spacing: 5

                    Button {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        enabled: (root.segmented ? root.editedDuration >= 0.05 :
                                      root.endTime - root.startTime >= 0.1) &&
                            (settingsStore.mp4ExportMode === "replace" && !root.segmented
                                ? (root.canReplace && !exportQueue.hasOutstanding &&
                                   !videoExportController.busy) : exportQueue.canQueue)
                        text: root.segmented && settingsStore.mp4ExportMode === "replace"
                            ? "MP4 copy" : settingsStore.mp4ExportMode === "replace" ? "Replace MP4" : "MP4"
                        onClicked: root.exportRequested()
                        font.bold: true
                        font.pixelSize: settingsStore.mp4ExportMode === "replace" ? 11 : 12
                        background: Rectangle {
                            radius: 7
                            color: !parent.enabled ? (root.tokens.panelBorder || "#444")
                                : settingsStore.mp4ExportMode === "replace"
                                    ? "#BD764A" : (root.tokens.accentSolid || "#2BFA83")
                        }
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: settingsStore.mp4ExportMode === "replace"
                                ? "#FFFFFF"
                                : (root.tokens.videoCardBackground || "#092111")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: "MP4: " + root.mp4ModeLabel()
                    }

                    Button {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        enabled: exportQueue.canQueue &&
                            (root.segmented ? root.editedDuration >= 0.05 :
                               root.endTime - root.startTime >= 0.1)
                        text: "GIF"
                        onClicked: root.exportGifRequested()
                        font.bold: true
                        font.pixelSize: 12
                        background: Rectangle {
                            radius: 7
                            color: root.tokens.accentTint || "#132319"
                            border.color: root.tokens.accentSolid || "#2BFA83"
                            border.width: 1
                        }
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: root.tokens.textPrimary || "white"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: "GIF: " + root.gifModeLabel()
                    }

                    Button {
                        id: settingsButton
                        Layout.preferredWidth: 36
                        Layout.fillHeight: true
                        text: "⚙"
                        onClicked: root.showExportModePopup()
                        font.pixelSize: 17
                        background: Rectangle {
                            radius: 7
                            color: root.tokens.accentTint || "#14231A"
                            border.color: root.tokens.panelBorder || "#375443"
                            border.width: 1
                        }
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: root.tokens.textPrimary || "white"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: "Configure MP4 and GIF export actions"
                    }
                }
            }



            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: "MP4: " + root.mp4ModeLabel()
                    font.pixelSize: 10
                    color: root.tokens.textSecondary || "#AAA"
                    elide: Text.ElideRight
                }
                Text {
                    text: "GIF: " + root.gifModeLabel()
                    font.pixelSize: 10
                    color: root.tokens.textSecondary || "#AAA"
                    elide: Text.ElideRight
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 15
                Layout.rightMargin: 15
                visible: settingsStore.mp4ExportMode === "replace"
                text: !root.canReplace
                    ? (root.segmented ? "Segment editing always exports a new copy."
                                      : "Replace original is only available for MP4.")
                    : exportQueue.hasOutstanding
                        ? "Replacement waits until the export queue finishes."
                        : settingsStore.keepBackupOnReplace
                            ? "Backup ON for original replacement."
                            : "Backup OFF: replacing cannot be undone."
                color: root.tokens.textSecondary || "#AAA"
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }

            Item { Layout.preferredHeight: 9 }
        }
    }
    Popup {
        id: exportModePopup
        parent: Overlay.overlay
        width: 318
        height: 370
        padding: 12
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: 11
            color: root.tokens.panelGlassStrong || "#111A13"
            border.color: root.tokens.accentSolid || "#2BFA83"
            border.width: 1
        }
        contentItem: ColumnLayout {
            spacing: 5
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "⚙  Export behavior"
                    color: root.tokens.textPrimary || "white"
                    font.pixelSize: 12
                    font.bold: true
                }
                Button {
                    text: "✕"
                    flat: true
                    onClicked: exportModePopup.close()
                    contentItem: Text {
                        text: parent.text
                        color: root.tokens.textSecondary || "#AAA"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
            Text {
                text: "WHEN YOU CLICK MP4"
                font.pixelSize: 9
                font.bold: true
                color: root.tokens.textMuted || "#888"
            }
            ModeChoice {
                text: "Export a copy automatically"
                detail: "Queue a uniquely named MP4 beside the source"
                selected: settingsStore.mp4ExportMode === "auto"
                onClicked: settingsStore.mp4ExportMode = "auto"
            }
            ModeChoice {
                text: "Choose name and folder"
                detail: "Open Windows Save As, then add to queue"
                selected: settingsStore.mp4ExportMode === "saveAs"
                onClicked: settingsStore.mp4ExportMode = "saveAs"
            }
            ModeChoice {
                text: "Replace original MP4"
                detail: "Confirm mode once; future MP4 clicks replace directly"
                selected: settingsStore.mp4ExportMode === "replace"
                enabled: root.canReplace
                onClicked: {
                    if (settingsStore.mp4ExportMode !== "replace") {
                        exportModePopup.close();
                        root.replaceModeRequested();
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.tokens.panelBorder || "#444"
            }
            Text {
                text: "WHEN YOU CLICK GIF"
                font.pixelSize: 9
                font.bold: true
                color: root.tokens.textMuted || "#888"
            }
            ModeChoice {
                text: "Export GIF automatically"
                detail: "Queue a uniquely named GIF beside the source"
                selected: settingsStore.gifExportMode === "auto"
                onClicked: settingsStore.gifExportMode = "auto"
            }
            ModeChoice {
                text: "Choose name and folder"
                detail: "Open Windows Save As, then add to queue"
                selected: settingsStore.gifExportMode === "saveAs"
                onClicked: settingsStore.gifExportMode = "saveAs"
            }
            Text {
                Layout.fillWidth: true
                text: "Backup preference remains in Tools → Settings."
                wrapMode: Text.WordWrap
                font.pixelSize: 9
                color: root.tokens.textMuted || "#888"
            }
        }
    }

}
