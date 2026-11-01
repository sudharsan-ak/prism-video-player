import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Prism

ApplicationWindow {
    id: prismWindow
    width: 1280
    height: 800
    minimumWidth: 700
    minimumHeight: 450
    visible: true
    title: "Prism"
    flags: Qt.Window | Qt.FramelessWindowHint
    // Taskbar/Alt-Tab/Explorer icon comes from the .rc-embedded icon.ico
    // compiled into the exe (CMakeLists.txt) - ApplicationWindow has no
    // settable "icon" property in this Qt version to also set here.

    property var tokens: themeController.tokens
    property bool libraryOpen: false
    property bool adjustmentsOpen: false
    property bool fullscreenMode: false

    property bool allowCloseWithExports: false
    onClosing: function(close) {
        if (!allowCloseWithExports &&
            (exportQueue.hasOutstanding || videoExportController.busy)) {
            close.accepted = false;
            closingExportsDialog.open();
        }
    }

    function requestClose() {
        prismWindow.close();
    }

    property bool editMode: false
    property string editSourcePath: ""
    property real editStart: 0
    property real editEnd: 0
    property bool previewSelectionPlaying: false
    property bool normalEditPlaybackPlaying: false
    EditSegments { id: editCuts }

    function splitEditSelection() {
        stopRangePreview();
        if (!editCuts.splitSelection(editStart,editEnd)) {
            toast.show(editCuts.warning, false);
        }
    }
    function deleteEditSegment() {
        stopRangePreview();
        if (!editCuts.softDelete()) toast.show(editCuts.warning || "Select a segment first.", false);
    }
    function seekEditVisual(t) {
        stopRangePreview();
        playerController.seek(editCuts.visualToSource(t));
    }
    function jumpNextKept() {
        const current = videoSurface.mpv ? videoSurface.mpv.position : 0;
        const next = editCuts.nextKeptStart(current);
        if (next >= 0) {
            stopRangePreview();
            playerController.seek(next);
        }
    }
    function toggleNormalEditPlayback() {
        if (!editMode) return;
        if (normalEditPlaybackPlaying && videoSurface.mpv && !videoSurface.mpv.paused) {
            stopRangePreview();
            return;
        }
        const mpv=videoSurface.mpv;
        if (!mpv) return;
        let current=mpv.position;
        const playable=!mpv.eofReached &&
            editCuts.keptRanges.some(r => current >= r.start && current < r.end-0.02);
        if (!playable) {
            const next=editCuts.keptRanges.find(r => r.start > current+0.0001);
            current=next ? next.start : editCuts.keptRanges.length ? editCuts.keptRanges[0].start : 0;
            playerController.seek(current);
        }
        previewSelectionPlaying=false;
        normalEditPlaybackPlaying=true;
        playerController.setSpeed(editSpeed);
        playerController.setPaused(false);
    }
    function queueEditSegments(gif,destination) {
        if (editCuts.hasCuts)
            return exportQueue.queueSegments(editSourcePath,editCuts.keptRanges,
                    destination,gif,editSpeed,editVolumePercent,editQuarterTurns,
                    editCropX,editCropY,editCropWidth,editCropHeight);
        return gif
            ? exportQueue.queueGif(editSourcePath, editStart, editEnd,
                                   destination, editSpeed, editQuarterTurns,
                                   editCropX, editCropY, editCropWidth, editCropHeight)
            : exportQueue.queueMp4(editSourcePath, editStart, editEnd,
                                   destination, editSpeed, editVolumePercent,
                                   editQuarterTurns, editCropX, editCropY,
                                   editCropWidth, editCropHeight);
    }
    property real editSpeed: 1.0
    property real normalPlaybackSpeed: 1.0
    property int editVolumePercent: 100
    property int lastEditAudibleVolume: 100
    property int normalPlaybackVolume: 80
    property bool normalMuted: false
    property int normalVideoRotation: 0
    property int editSourceWidth: 0
    property int editSourceHeight: 0
    property int editQuarterTurns: 0
    property bool cropGuidesVisible: false
    property real editCropX: 0
    property real editCropY: 0
    property real editCropWidth: 1
    property real editCropHeight: 1

    function setEditCrop(x, y, w, h) {
        const cw = Math.max(0.05, Math.min(1, Number(w)));
        const ch = Math.max(0.05, Math.min(1, Number(h)));
        editCropWidth = cw;
        editCropHeight = ch;
        editCropX = Math.max(0, Math.min(1 - cw, Number(x)));
        editCropY = Math.max(0, Math.min(1 - ch, Number(y)));
    }

    function resetEditCrop() { setEditCrop(0, 0, 1, 1); }

    function setCropPreset(preset) {
        if (preset === "Full") {
            resetEditCrop();
            return;
        }
        const ratio = preset === "1:1" ? 1 :
                      preset === "16:9" ? 16 / 9 :
                      preset === "9:16" ? 9 / 16 : 0;
        if (ratio <= 0)
            return;
        const w = editQuarterTurns % 2 ? editSourceHeight : editSourceWidth;
        const h = editQuarterTurns % 2 ? editSourceWidth : editSourceHeight;
        if (w <= 0 || h <= 0)
            return;
        const sourceRatio = w / h;
        const cw = Math.min(1, ratio / sourceRatio);
        const ch = Math.min(1, sourceRatio / ratio);
        setEditCrop((1 - cw) / 2, (1 - ch) / 2, cw, ch);
        cropGuidesVisible = true;
    }

    function setEditRotation(turns) {
        const target = ((Math.round(turns) % 4) + 4) % 4;
        let delta = (target - editQuarterTurns + 4) % 4;
        let x = editCropX, y = editCropY, w = editCropWidth, h = editCropHeight;
        while (delta-- > 0) {
            const oldX = x, oldY = y, oldW = w, oldH = h;
            x = 1 - oldY - oldH;
            y = oldX;
            w = oldH;
            h = oldW;
        }
        editQuarterTurns = target;
        setEditCrop(x, y, w, h);
        playerController.setRotation(target);
    }

    function restorePlaybackRotation() {
        if (videoSurface.mpv)
            videoSurface.mpv.setProperty("video-rotate", normalVideoRotation);
    }

    function setEditVolume(percent) {
        const value = Math.max(0, Math.min(100, Math.round(percent)));
        editVolumePercent = value;
        if (value > 0)
            lastEditAudibleVolume = value;
        // Do not persist the normal player's saved volume.
        if (videoSurface.mpv) {
            videoSurface.mpv.setProperty("volume", value);
            videoSurface.mpv.setProperty("mute", value === 0);
        }
    }

    function restorePlaybackAudio() {
        if (videoSurface.mpv) {
            videoSurface.mpv.setProperty("volume", normalPlaybackVolume);
            videoSurface.mpv.setProperty("mute", normalMuted);
        }
    }


    function stopRangePreview() {
        previewSelectionPlaying = false;
        normalEditPlaybackPlaying = false;
        playerController.setPaused(true);
    }

    function toggleEditPlayback() {
        if (!editMode || editEnd - editStart < 0.1)
            return;
        if (previewSelectionPlaying && videoSurface.mpv && !videoSurface.mpv.paused) {
            stopRangePreview();
            return;
        }
        const mpv = videoSurface.mpv;
        // Play Range explicitly starts at IN. Normal Play remains at
        // the manually chosen playhead position.
        const within = editCuts.keptRanges.find(r=>r.end > editStart+0.001 && r.start < editEnd);
        if (!within) return;
        playerController.seek(Math.max(editStart,within.start));
        playerController.setSpeed(editSpeed);
        normalEditPlaybackPlaying = false;
        previewSelectionPlaying = true;
        playerController.setPaused(false);
    }

    function beginEditing() {
        const mpv = videoSurface.mpv;
        if (!mpv || !mpv.mediaPath || mpv.videoWidth <= 0 || mpv.duration <= 0) {
            toast.show("Open a video and wait for it to load before editing.", true);
            return;
        }
        if (videoExportController.busy && !exportQueue.hasOutstanding) {
            toast.show("Finish replacing the original video before editing.", true);
            return;
        }
        if (fullscreenMode)
            toggleFullscreen();
        normalPlaybackSpeed = mpv.speed;
        const originalMute = String(mpv.getProperty("mute")).toLowerCase();
        normalMuted = originalMute === "yes" || originalMute === "true" || originalMute === "1";
        normalPlaybackVolume = mpv.volume;
        const priorRotation = Number(mpv.getProperty("video-rotate"));
        normalVideoRotation = isFinite(priorRotation) ? priorRotation : 0;
        editSourceWidth = mpv.videoWidth;
        editSourceHeight = mpv.videoHeight;
        editQuarterTurns = 0;
        cropGuidesVisible = false;
        resetEditCrop();
        playerController.setRotation(0);
        lastEditAudibleVolume = 100;
        setEditVolume(100); // Default to original source gain.
        editSpeed = 1.0;
        playerController.setSpeed(1.0);
        editSourcePath = mpv.mediaPath;
        editStart = 0;
        editEnd = mpv.duration;
        editCuts.reset(mpv.duration);
        previewSelectionPlaying = false;
        normalEditPlaybackPlaying = false;
        playerController.setPaused(true);
        libraryOpen = false;
        adjustmentsOpen = false;
        editMode = true;
        videoThumbnailController.generate(editSourcePath, mpv.duration);
        globalShortcuts.forceActiveFocus();
    }

    function leaveEditing() {
        if (videoExportController.busy && !exportQueue.hasOutstanding) {
            toast.show("Finish replacing the original before leaving Edit mode.", false);
            return;
        }
        previewSelectionPlaying = false;
        normalEditPlaybackPlaying = false;
        playerController.setPaused(true);
        playerController.setSpeed(normalPlaybackSpeed);
        restorePlaybackAudio();
        restorePlaybackRotation();
        editMode = false;
        videoThumbnailController.stop();
        globalShortcuts.forceActiveFocus();
    }

    function previewEditRange() {
        toggleEditPlayback();
    }

    function enqueueCurrentTrim(animatedGif) {
        if (!editMode || !exportQueue.canQueue)
            return;
        const destination = exportQueue.suggestedOutputUrl(editSourcePath, animatedGif);
        if (!destination || destination.toString().length === 0) {
            toast.show("Could not find an available output filename. Choose a location instead.", true);
            return;
        }
        const ok = queueEditSegments(animatedGif,destination);
        if (!ok) {
            toast.show(exportQueue.lastError, true);
            return;
        }
        toast.show((animatedGif ? "GIF" : "MP4") + " added to export queue.", false);
    }


    function triggerMp4Export() {
        if (!editMode)
            return;
        const mode = settingsStore.mp4ExportMode;
        if (mode === "saveAs") {
            openTrimSaveDialog();
        } else if (mode === "replace" && editCuts.hasCuts) {
            // A segmented edit cannot overwrite the source video.
            // Keep the saved preference, but force a new queued copy.
            enqueueCurrentTrim(false);
        } else if (mode === "replace") {
            if (!editSourcePath.toLowerCase().endsWith(".mp4")) {
                toast.show("Replacing the original is available only for MP4 files.", true);
                return;
            }
            if (exportQueue.hasOutstanding || videoExportController.busy) {
                toast.show("Finish queued exports before replacing the original.", true);
                return;
            }
            // User already acknowledged this destructive export mode when
            // selecting it in the settings popup. Do not prompt again.
            stopRangePreview();
            if (!videoExportController.startReplaceTrim(editSourcePath, editStart,
                                                         editEnd, editSpeed,
                                                         editVolumePercent, editQuarterTurns,
                                                         editCropX, editCropY,
                                                         editCropWidth, editCropHeight)) {
                toast.show(videoExportController.error || "Could not start replacement.", true);
            }
        } else {
            enqueueCurrentTrim(false);
        }
    }

    function triggerGifExport() {
        if (!editMode)
            return;
        if (settingsStore.gifExportMode === "saveAs")
            openGifSaveDialog();
        else
            enqueueCurrentTrim(true);
    }

    function openGifSaveDialog() {
        if (!editMode || !exportQueue.canQueue)
            return;
        gifSaveDialog.selectedFile = exportQueue.suggestedOutputUrl(editSourcePath, true);
        gifSaveDialog.open();
    }

    function openTrimSaveDialog() {
        if (!editMode || !exportQueue.canQueue)
            return;
        trimSaveDialog.selectedFile = exportQueue.suggestedOutputUrl(editSourcePath, false);
        trimSaveDialog.open();
    }

    color: "transparent"

    function toggleFullscreen() {
        if (editMode) {
            toast.show("Exit Edit mode before entering fullscreen.", false);
            return;
        }
        if (visibility === Window.FullScreen) {
            visibility = Window.Windowed;
            fullscreenMode = false;
        } else {
            visibility = Window.FullScreen;
            fullscreenMode = true;
        }
        // Re-claim focus so Escape/Space/etc keep working regardless of
        // what had focus before the switch (e.g. a panel control) -
        // fullscreen's Escape-to-exit was silently dead without this.
        globalShortcuts.forceActiveFocus();
    }

    function openAdjustments() {
        adjustmentsOpen = true;
    }

    function toggleAdjustments() {
        adjustmentsOpen = !adjustmentsOpen;
    }

    function openSettingsMenu() {
        // Context menu's Settings shortcut opens the Adjustments panel,
        // the closest equivalent to a Settings surface reachable from
        // over the video (PHASE1_PLAN_QT.md section 6.3).
        adjustmentsOpen = true;
    }

    function toggleShortcutsPanel() {
        shortcutsOverlay.visible = !shortcutsOverlay.visible;
    }

    function toggleAboutPanel() {
        aboutOverlay.visible = !aboutOverlay.visible;
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: tokens.backgroundGradient ? tokens.backgroundGradient[0] : "#F5F1E6" }
            GradientStop { position: 0.55; color: tokens.backgroundGradient ? tokens.backgroundGradient[1] : "#EDE6D6" }
            GradientStop { position: 1.0; color: tokens.backgroundGradient ? tokens.backgroundGradient[2] : "#E6DCC6" }
        }
    }

    ColumnLayout {
        id: windowedChrome
        anchors.fill: parent
        spacing: 0
        visible: !prismWindow.fullscreenMode

        TopBar {
            id: topBar
            Layout.fillWidth: true
            mpv: videoSurface.mpv
            libraryOpen: prismWindow.libraryOpen
            adjustmentsOpen: prismWindow.adjustmentsOpen
            editorActive: prismWindow.editMode
            outstandingExports: exportQueue.waitingCount + (exportQueue.hasOutstanding && videoExportController.busy ? 1 : 0)
            onQueueRequested: exportQueuePopup.open()
            onEditRequested: prismWindow.editMode ? prismWindow.leaveEditing() : prismWindow.beginEditing()
            onLibraryToggled: prismWindow.libraryOpen = !prismWindow.libraryOpen
            onAdjustmentsToggled: prismWindow.adjustmentsOpen = !prismWindow.adjustmentsOpen
            onOpenFilesRequested: openFilesDialog.open()
            onAddFolderRequested: addFolderDialog.open()
            onLoadSubtitleRequested: subtitleDialog.open()
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            LibraryPanel {
                id: libraryPanel
                Layout.fillHeight: true
                visible: prismWindow.libraryOpen && !prismWindow.editMode
                mpv: videoSurface.mpv
                onAddFilesRequested: addToQueueDialog.open()
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Item {
                    id: videoStage
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        anchors.fill: parent
                        radius: 0
                        color: tokens.videoCardBackground || "#141210"
                        clip: true

                        Item {
                            id: windowedVideoSlot
                            anchors.fill: parent
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !videoSurface.mpv || !videoSurface.mpv.mediaPath
                            text: "Open a video to get started"
                            font.pixelSize: 13
                            color: "#555"
                        }
                    }
                }

                BottomControlBar {
                    id: bottomBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 92
                    visible: !prismWindow.editMode
                    mpv: videoSurface.mpv
                }

                EditorTimeline {
                    id: editorTimeline
                    Layout.fillWidth: true
                    Layout.preferredHeight: 365
                    visible: prismWindow.editMode
                    enabled: exportQueue.canQueue
                    duration: editCuts.visualDuration
                    sourceDuration: editCuts.sourceDuration
                    displaySegments: editCuts.displaySegments
                    selectedSegmentId: editCuts.selectedId
                    keptDuration: editCuts.keptDuration
                    keptPosition: editCuts.sourceToKept(videoSurface.mpv ? videoSurface.mpv.position : 0)
                    segmentEditing: editCuts.hasCuts
                    segmentWarning: editCuts.warning
                    canUndo: editCuts.canUndo
                    canRedo: editCuts.canRedo
                    selectedRemoved: editCuts.selected ? editCuts.selected.removed : false
                    selectedCollapsed: editCuts.selected ? editCuts.selected.collapsed : false
                    canSoftDelete: editCuts.selected && !editCuts.selected.removed &&
                        editCuts.keptRanges.length > 1
                    hasNextKept: editCuts.nextKeptStart(
                        videoSurface.mpv ? videoSurface.mpv.position : 0) >= 0
                    position: editCuts.sourceToVisual(videoSurface.mpv ? videoSurface.mpv.position : 0)
                    startTime: editCuts.sourceToVisual(prismWindow.editStart)
                    endTime: editCuts.sourceToVisual(prismWindow.editEnd)
                    editSpeed: prismWindow.editSpeed
                    audioVolumePercent: prismWindow.editVolumePercent
                    lastAudibleVolume: prismWindow.lastEditAudibleVolume
                    onAudioVolumeEdited: function(percent) { prismWindow.setEditVolume(percent); }
                    previewPlaying: (prismWindow.previewSelectionPlaying ||
                        prismWindow.normalEditPlaybackPlaying) &&
                        videoSurface.mpv && !videoSurface.mpv.paused
                    onTogglePlaybackRequested: prismWindow.toggleEditPlayback()
                    onSpeedEdited: function(value) {
                        prismWindow.editSpeed = value;
                        playerController.setSpeed(value);
                    }
                    sourceIsMp4: prismWindow.editSourcePath.toLowerCase().endsWith(".mp4")
                    onRangeMoveStarted: prismWindow.stopRangePreview()
                    onRangeMoved: function(newStart, newEnd) {
                        const a=editCuts.visualToSource(newStart);
                        const b=editCuts.visualToSource(newEnd);
                        if (a > prismWindow.editStart) {
                            prismWindow.editEnd=b;
                            prismWindow.editStart=a;
                        } else {
                            prismWindow.editStart=a;
                            prismWindow.editEnd=b;
                        }
                    }
                    onRangeMoveFinished: function(newStart) {
                        // Trimming and shifting a range never seeks the video.
                    }
                    onStartTimeEdited: function(seconds) {
                        prismWindow.stopRangePreview();
                        prismWindow.editStart=Math.max(0,Math.min(
                            editCuts.visualToSource(seconds),prismWindow.editEnd-0.05));
                    }
                    onEndTimeEdited: function(seconds) {
                        prismWindow.stopRangePreview();
                        prismWindow.editEnd=Math.min(editCuts.sourceDuration,Math.max(
                            editCuts.visualToSource(seconds),prismWindow.editStart+0.05));
                    }
                    onSeekRequested: function(seconds) { prismWindow.seekEditVisual(seconds); }
                    onPlaybackSeekRequested: function(seconds) {
                        prismWindow.stopRangePreview();
                        playerController.seek(editCuts.keptToSource(seconds));
                    }
                    onSplitRequested: prismWindow.splitEditSelection()
                    onSoftDeleteRequested: prismWindow.deleteEditSegment()
                    onRestoreSegmentRequested: {
                        prismWindow.stopRangePreview();
                        editCuts.restore();
                    }
                    onRemoveGapRequested: function(id) {
                        prismWindow.stopRangePreview();
                        editCuts.select(id);
                        editCuts.removeGap();
                    }
                    onUndoRequested: { prismWindow.stopRangePreview(); editCuts.undo(); }
                    onRedoRequested: { prismWindow.stopRangePreview(); editCuts.redo(); }
                    onJumpNextRequested: prismWindow.jumpNextKept()
                    onNormalPlaybackRequested: prismWindow.toggleNormalEditPlayback()
                    onBeginningRequested: {
                        prismWindow.stopRangePreview();
                        if (editCuts.keptRanges.length > 0)
                            playerController.seek(editCuts.keptRanges[0].start);
                    }
                    onResetAllRequested: {
                        prismWindow.stopRangePreview();
                        editCuts.resetEdits();
                        prismWindow.editStart = 0;
                        prismWindow.editEnd = editCuts.sourceDuration;
                    }
                    onSegmentSelected: function(id) { editCuts.select(id); }
                    onSegmentSelectedAt: function(t) {
                        const source=editCuts.visualToSource(t);
                        const seg=editCuts.segments.find(x=>x.start<=source && x.end>source);
                        if(seg) editCuts.select(seg.id);
                    }
                    onPreviewRequested: prismWindow.previewEditRange()
                    onResetRequested: {
                        prismWindow.stopRangePreview();
                        prismWindow.editStart = 0;
                        prismWindow.editEnd = videoSurface.mpv ? videoSurface.mpv.duration : 0;
                    }
                    onExportRequested: prismWindow.triggerMp4Export()
                }
            }

            AdjustmentsPanel {
                id: adjustmentsPanel
                Layout.fillHeight: true
                visible: prismWindow.adjustmentsOpen && !prismWindow.editMode
                mpv: videoSurface.mpv
                onCloseRequested: prismWindow.adjustmentsOpen = false
            }

            EditorPanel {
                id: editorPanel
                Layout.fillHeight: true
                Layout.preferredWidth: 305
                visible: prismWindow.editMode
                sourceTitle: prismWindow.editSourcePath.split(/[\\\\\\/]/).pop()
                sourcePath: prismWindow.editSourcePath
                startTime: prismWindow.editStart
                endTime: prismWindow.editEnd
                duration: editCuts.keptDuration
                segmented: editCuts.hasCuts
                editedDuration: editCuts.keptDuration
                originalDuration: editCuts.sourceDuration
                visualDuration: editCuts.visualDuration
                previewTime: editCuts.sourceToKept(videoSurface.mpv ? videoSurface.mpv.position : 0)
                segmentCount: editCuts.keptRanges.length
                segmentItems: editCuts.segments
                selectedSegmentId: editCuts.selectedId
                onSelectSegmentRequested: function(id) { editCuts.select(id); }
                onRestoreSegmentRequested: function(id) {
                    prismWindow.stopRangePreview();
                    editCuts.select(id);
                    editCuts.restore();
                }
                editSpeed: prismWindow.editSpeed
                audioVolumePercent: prismWindow.editVolumePercent
                cropActive: prismWindow.cropGuidesVisible
                cropX: prismWindow.editCropX
                cropY: prismWindow.editCropY
                cropWidth: prismWindow.editCropWidth
                cropHeight: prismWindow.editCropHeight
                quarterTurns: prismWindow.editQuarterTurns
                onCropModeToggled: prismWindow.cropGuidesVisible = !prismWindow.cropGuidesVisible
                onCropResetRequested: prismWindow.resetEditCrop()
                onCropPresetRequested: function(preset) { prismWindow.setCropPreset(preset); }
                onRotationRequested: function(turns) { prismWindow.setEditRotation(turns); }
                onCloseRequested: prismWindow.leaveEditing()
                onExportRequested: prismWindow.triggerMp4Export()
                onExportGifRequested: prismWindow.triggerGifExport()
                onReplaceModeRequested: replaceModeConfirmDialog.open()
                onQueueRequested: exportQueuePopup.open()
                 onPreviewRequested: prismWindow.previewEditRange()
                onResetRequested: {
                    prismWindow.editStart = 0;
                    prismWindow.editEnd = videoSurface.mpv ? videoSurface.mpv.duration : 0;
                }
            }
        }
    }

    Item {
        id: fullscreenChrome
        anchors.fill: parent
        visible: prismWindow.fullscreenMode

        Item {
            id: fullscreenVideoSlot
            anchors.fill: parent
        }

        FullscreenOverlay {
            id: fullscreenOverlay
            anchors.fill: parent
            mpv: videoSurface.mpv
        }
    }

    // One MpvObject for the whole app's life: toggling fullscreen moves
    // this single video item between the windowed and fullscreen slot
    // instead of creating a second engine instance, so playback state
    // never resets (PHASE1_PLAN_QT.md section 6.8).
    VideoSurface {
        id: videoSurface
        anchors.fill: parent
        parent: windowedVideoSlot
        onContextMenuRequested: function(pos) {
            contextMenu.mpv = videoSurface.mpv;
            contextMenu.popup(videoSurface, pos.x, pos.y);
        }
        onMouseActivity: {
            if (prismWindow.fullscreenMode)
                fullscreenOverlay.notifyActivity();
        }
        onDoubleClicked: {
            if (prismWindow.editMode) prismWindow.toggleNormalEditPlayback();
            else playerController.togglePause();
        }
        onSingleClicked: {
            // Single click never touches playback - only toggles the
            // floating overlay's visibility in fullscreen, per explicit
            // feedback that clicking the video was wrongly firing
            // play/pause. Double click (VideoSurface.onDoubleClicked)
            // is the only click gesture that plays/pauses.
            if (prismWindow.fullscreenMode)
                fullscreenOverlay.toggleVisibility();
        }
    }

    onFullscreenModeChanged: {
        videoSurface.parent = fullscreenMode ? fullscreenVideoSlot : windowedVideoSlot;
        videoSurface.anchors.fill = videoSurface.parent;
    }

    CropOverlay {
        id: cropOverlay
        parent: windowedVideoSlot
        anchors.fill: parent
        z: 10
        visible: prismWindow.editMode && prismWindow.cropGuidesVisible
        enabled: visible && exportQueue.canQueue
        sourceWidth: prismWindow.editSourceWidth
        sourceHeight: prismWindow.editSourceHeight
        quarterTurns: prismWindow.editQuarterTurns
        cropX: prismWindow.editCropX
        cropY: prismWindow.editCropY
        cropWidth: prismWindow.editCropWidth
        cropHeight: prismWindow.editCropHeight
        onCropEdited: function(x, y, w, h) {
            prismWindow.setEditCrop(x, y, w, h);
        }
    }

    ContextMenu {
        id: contextMenu
    }

    // Visible feedback for PlayerController.notify() (screenshot saved,
    // screenshot failed, invalid file, etc.) - these previously only
    // reached console.log, which is invisible in a release build with
    // no console, so a failure (like the screenshot bug) looked like
    // the button silently did nothing.
    Rectangle {
        id: toast
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 170
        width: toastText.implicitWidth + 32
        height: 36
        radius: 10
        opacity: 0
        z: 50
        color: toastIsError ? "#D64545" : (tokens.panelGlassStrong || "#222")
        property bool toastIsError: false

        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            id: toastText
            anchors.centerIn: parent
            color: "white"
            font.pixelSize: 12
        }

        Timer {
            id: toastTimer
            interval: 2800
            onTriggered: toast.opacity = 0
        }

        function show(message, isError) {
            toastText.text = message;
            toastIsError = isError;
            opacity = 1;
            toastTimer.restart();
        }
    }

    Connections {
        target: playerController
        function onNotify(message, type) {
            toast.show(message, type === "error");
        }
    }

    OsdOverlay {
        id: osd
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 120
    }

    Rectangle {
        id: shortcutsOverlay
        visible: false
        anchors.centerIn: parent
        width: 420
        height: 260
        radius: 14
        color: tokens.panelGlassStrong || "#fff"
        border.color: tokens.panelBorder || "#ccc"
        border.width: 1
        z: 100

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 8

            Text { text: "Keyboard shortcuts"; font.pixelSize: 14; font.weight: Font.Bold; color: tokens.textPrimary }
            Text { text: "Space: Play / Pause"; font.pixelSize: 11; color: tokens.textSecondary }
            Text { text: "Left / Right: ±5 sec"; font.pixelSize: 11; color: tokens.textSecondary }
            Text { text: "Shift + Left / Right: ±30 sec"; font.pixelSize: 11; color: tokens.textSecondary }
            Text { text: "Up / Down: Volume"; font.pixelSize: 11; color: tokens.textSecondary }
            Text { text: "F: Fullscreen"; font.pixelSize: 11; color: tokens.textSecondary }
            Text { text: "O: Open files"; font.pixelSize: 11; color: tokens.textSecondary }
            Text { text: "[ / ]: Playback speed"; font.pixelSize: 11; color: tokens.textSecondary }
            Text { text: "S: Screenshot"; font.pixelSize: 11; color: tokens.textSecondary }
            Text { text: "B: Bookmark"; font.pixelSize: 11; color: tokens.textSecondary }
        }
        MouseArea { anchors.fill: parent; onClicked: {} }
    }
    MouseArea {
        anchors.fill: parent
        visible: shortcutsOverlay.visible || aboutOverlay.visible
        onClicked: { shortcutsOverlay.visible = false; aboutOverlay.visible = false; }
    }

    Rectangle {
        id: aboutOverlay
        visible: false
        anchors.centerIn: parent
        width: 340
        height: 160
        radius: 14
        color: tokens.panelGlassStrong || "#fff"
        border.color: tokens.panelBorder || "#ccc"
        border.width: 1
        z: 100

        Column {
            anchors.centerIn: parent
            spacing: 8
            Text { text: "Prism"; font.pixelSize: 16; font.weight: Font.Black; color: tokens.textPrimary; anchors.horizontalCenter: parent.horizontalCenter }
            Text { text: "A local-only, offline-first media player."; font.pixelSize: 11; color: tokens.textSecondary; anchors.horizontalCenter: parent.horizontalCenter }
            Text { text: "No accounts. No ads. No tracking."; font.pixelSize: 11; color: tokens.textMuted; anchors.horizontalCenter: parent.horizontalCenter }
        }
    }

    FileDialog {
        id: openFilesDialog
        title: "Open local video or audio"
        fileMode: FileDialog.OpenFiles
        onAccepted: playerController.openFiles(selectedFiles.map(u => u.toString().replace("file:///", "")))
    }

    FileDialog {
        id: addToQueueDialog
        title: "Add files to queue"
        fileMode: FileDialog.OpenFiles
        onAccepted: playerController.addToQueue(selectedFiles.map(u => u.toString().replace("file:///", "")))
    }

    FolderDialog {
        id: addFolderDialog
        title: "Add folder to queue"
        onAccepted: {
            // Folder expansion to individual files happens through the
            // controller once a user selects one; Prism keeps file
            // picking local-only, matching PHASE1_PLAN_QT.md section 5.3.
        }
    }

    Dialog {
        id: replaceModeConfirmDialog
        parent: Overlay.overlay
        modal: true
        focus: true
        x: Math.round((prismWindow.width - width) / 2)
        y: Math.round((prismWindow.height - height) / 2)
        width: Math.min(478, prismWindow.width - 36)
        height: Math.min(382, prismWindow.height - 28)
        padding: 0
        // A custom header and footer prevent Qt's native button palette
        // from appearing in light themes or ignoring Prism's hover styles.
        header: null
        footer: null
        standardButtons: Dialog.NoButton
        closePolicy: Popup.CloseOnEscape

        // Pick accessible text contrast for every theme's solid accent.
        function accentForeground() {
            const hex = String(prismWindow.tokens.accentSolid || "#39FF88").replace("#", "");
            if (hex.length !== 6)
                return "#111111";
            const channel = function(i) {
                const v = parseInt(hex.substring(i, i + 2), 16) / 255;
                return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
            };
            const luminance = 0.2126 * channel(0) +
                              0.7152 * channel(2) + 0.0722 * channel(4);
            return luminance > 0.179 ? "#111111" : "#FFFFFF";
        }

        onAccepted: {
            if (!prismWindow.editMode ||
                !prismWindow.editSourcePath.toLowerCase().endsWith(".mp4"))
                return;
            // Explicit approval only changes the selected mode.
            // No export runs when this dialog is accepted.
            settingsStore.confirmReplaceMode();
            toast.show("Replace MP4 enabled. Future clicks replace without another prompt.", false);
        }

        background: Rectangle {
            radius: 14
            color: prismWindow.tokens.panelGlassStrong || "#202129"
            border.width: 1
            border.color: prismWindow.tokens.accentSolid || "#39FF88"
        }

        contentItem: ColumnLayout {
            spacing: 0

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 61
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 12
                    spacing: 10
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Text {
                            text: "Enable one-click replacement?"
                            color: prismWindow.tokens.textPrimary || "#FFFFFF"
                            font.pixelSize: 15
                            font.bold: true
                        }
                        Text {
                            text: "MP4 export behavior"
                            color: prismWindow.tokens.textSecondary || "#AAAAAA"
                            font.pixelSize: 11
                        }
                    }
                    Button {
                        id: replaceDialogClose
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        text: "✕"
                        onClicked: replaceModeConfirmDialog.reject()
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        background: Rectangle {
                            radius: 7
                            color: replaceDialogClose.hovered
                                ? (prismWindow.tokens.accentTint || "#2439FF88")
                                : "transparent"
                            border.width: replaceDialogClose.activeFocus ? 1 : 0
                            border.color: prismWindow.tokens.accentSolid || "#39FF88"
                        }
                        contentItem: Text {
                            text: replaceDialogClose.text
                            font.pixelSize: 12
                            color: prismWindow.tokens.textPrimary || "#FFFFFF"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: "Close without enabling"
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: prismWindow.tokens.panelBorder || "#444444"
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    width: parent.width
                    spacing: 13

                    Item { Layout.preferredHeight: 3 }

                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 18
                        Layout.rightMargin: 18
                        text: "Once enabled, clicking Replace MP4 will immediately replace the original with your selected trim. No further confirmation will appear."
                        color: prismWindow.tokens.textPrimary || "#FFFFFF"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 18
                        Layout.rightMargin: 18
                        implicitHeight: backupInfo.implicitHeight + 24
                        radius: 8
                        color: prismWindow.tokens.accentTint || "#2439FF88"
                        border.width: 1
                        border.color: prismWindow.tokens.accentSolid || "#39FF88"
                        ColumnLayout {
                            id: backupInfo
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 4
                            Text {
                                text: settingsStore.keepBackupOnReplace
                                    ? "BACKUP ENABLED" : "BACKUP DISABLED"
                                color: prismWindow.tokens.textPrimary || "#FFFFFF"
                                font.pixelSize: 10
                                font.bold: true
                            }
                            Text {
                                Layout.fillWidth: true
                                text: settingsStore.keepBackupOnReplace
                                    ? "Prism will retain a timestamped copy of the original."
                                    : "Your original will be overwritten without a backup. This cannot be undone."
                                wrapMode: Text.WordWrap
                                color: prismWindow.tokens.textPrimary || "#FFFFFF"
                                font.pixelSize: 11
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 18
                        Layout.rightMargin: 18
                        text: "The current trim range, speed and audio volume will be used. Replacement is unavailable while other exports are queued."
                        color: prismWindow.tokens.textSecondary || "#AAAAAA"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 18
                        Layout.rightMargin: 18
                        text: "You can change this behavior later using the gear."
                        color: prismWindow.tokens.textMuted || "#888888"
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }

                    Item { Layout.preferredHeight: 8 }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: prismWindow.tokens.panelBorder || "#444444"
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 66
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    anchors.topMargin: 12
                    anchors.bottomMargin: 12
                    spacing: 10
                    Item { Layout.fillWidth: true }
                    Button {
                        id: cancelReplaceMode
                        Layout.preferredWidth: 102
                        Layout.fillHeight: true
                        text: "Cancel"
                        onClicked: replaceModeConfirmDialog.reject()
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        background: Rectangle {
                            radius: 8
                            color: cancelReplaceMode.down
                                ? (prismWindow.tokens.accentTint || "#2439FF88")
                                : cancelReplaceMode.hovered
                                    ? (prismWindow.tokens.accentTint || "#2439FF88")
                                    : (prismWindow.tokens.panelGlass || "#25262D")
                            border.width: 1
                            border.color: cancelReplaceMode.hovered || cancelReplaceMode.activeFocus
                                ? (prismWindow.tokens.accentSolid || "#39FF88")
                                : (prismWindow.tokens.panelBorder || "#444444")
                        }
                        contentItem: Text {
                            text: cancelReplaceMode.text
                            color: prismWindow.tokens.textPrimary || "#FFFFFF"
                            font.pixelSize: 12
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Button {
                        id: enableReplaceMode
                        Layout.preferredWidth: 178
                        Layout.fillHeight: true
                        text: "Enable Replace MP4"
                        onClicked: replaceModeConfirmDialog.accept()
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        background: Rectangle {
                            radius: 8
                            color: enableReplaceMode.down
                                ? Qt.darker(prismWindow.tokens.accentSolid || "#39FF88", 1.18)
                                : enableReplaceMode.hovered
                                    ? Qt.lighter(prismWindow.tokens.accentSolid || "#39FF88", 1.12)
                                    : (prismWindow.tokens.accentSolid || "#39FF88")
                            border.width: enableReplaceMode.activeFocus ? 2 : 0
                            border.color: prismWindow.tokens.textPrimary || "#FFFFFF"
                        }
                        contentItem: Text {
                            text: enableReplaceMode.text
                            color: replaceModeConfirmDialog.accentForeground()
                            font.pixelSize: 12
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
    FileDialog {
        id: trimSaveDialog
        title: "Export trimmed video (new MP4)"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "mp4"
        nameFilters: ["MP4 video (*.mp4)"]
        onAccepted: {
            if (!prismWindow.queueEditSegments(false,selectedFile))
                toast.show(exportQueue.lastError, true);
            else
                toast.show("MP4 added to export queue.", false);
        }
    }

    FileDialog {
        id: gifSaveDialog
        title: "Export animated GIF (silent, looping)"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "gif"
        nameFilters: ["Animated GIF (*.gif)"]
        onAccepted: {
            if (!prismWindow.queueEditSegments(true,selectedFile))
                toast.show(exportQueue.lastError, true);
            else
                toast.show("GIF added to export queue.", false);
        }
    }

    Popup {
        id: exportQueuePopup
        parent: Overlay.overlay
        modal: false
        focus: true
        x: Math.max(8, prismWindow.width - width - 16)
        y: 48
        width: Math.min(380, prismWindow.width - 16)
        height: Math.min(440, prismWindow.height - 60)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: 10
            color: prismWindow.tokens.panelGlassStrong || "#242331"
            border.width: 1
            border.color: prismWindow.tokens.panelBorder || "#444"
        }
        contentItem: ExportQueuePanel { }
    }

    Dialog {
        id: closingExportsDialog
        modal: true
        width: Math.min(440, prismWindow.width - 40)
        anchors.centerIn: parent
        title: "Exports are still running"
        standardButtons: Dialog.Yes | Dialog.No
        contentItem: Text {
            width: 390
            wrapMode: Text.WordWrap
            text: "Closing Prism will stop the active export and discard the waiting queue. Exit anyway?"
            font.pixelSize: 12
            color: prismWindow.tokens.textPrimary || "#fff"
        }
        background: Rectangle {
            color: prismWindow.tokens.panelGlassStrong || "#242331"
            border.color: prismWindow.tokens.panelBorder || "#444"
            radius: 10
        }
        onAccepted: {
            prismWindow.allowCloseWithExports = true;
            prismWindow.close();
        }
    }

    Connections {
        target: videoExportController
        function onReplacementPrepared() {
            prismWindow.previewSelectionPlaying = false;
            playerController.setPaused(true);
            playerController.setSpeed(prismWindow.normalPlaybackSpeed);
            prismWindow.restorePlaybackAudio();
            prismWindow.restorePlaybackRotation();
            prismWindow.editMode = false;
            videoThumbnailController.stop();
            // Release the source handle before Windows can replace it.
            videoSurface.mpv.command(["stop"]);
            videoExportController.completeReplacement();
        }
        function onCompleted(outputUrl) {
            if (videoExportController.lastWasReplacement) {
                settingsStore.clearResumePositionFor(prismWindow.editSourcePath);
                playerController.openFiles([prismWindow.editSourcePath]);
                toast.show(videoExportController.backupPath.length > 0
                           ? "Original replaced. Backup saved beside it."
                           : "Original replaced successfully.", false);
            } else if (videoExportController.error.length > 0) {
                toast.show("Replacement not confirmed. Edited copy saved. Inspect original.", true);
            } else if (outputUrl.toString().toLowerCase().endsWith(".gif")) {
                toast.show("Animated GIF saved successfully.", false);
            } else {
                toast.show("Edited video saved successfully.", false);
            }
        }
    }

    FileDialog {
        id: subtitleDialog
        title: "Load subtitles"
        nameFilters: ["Subtitle files (*.srt *.ass *.ssa *.vtt *.sub *.idx *.smi)"]
        onAccepted: playerController.loadExternalSubtitle(selectedFile.toString().replace("file:///", ""))
    }

    Connections {
        target: videoSurface.mpv
        function onVolumeChanged() {
            osd.show("Volume", videoSurface.mpv.volume, 100);
        }
        function onEofReachedChanged() {
            if (prismWindow.editMode && videoSurface.mpv && videoSurface.mpv.eofReached &&
                (prismWindow.normalEditPlaybackPlaying || prismWindow.previewSelectionPlaying))
                prismWindow.stopRangePreview();
        }
        function onPositionChanged() {
            if (!prismWindow.editMode ||
                (!prismWindow.previewSelectionPlaying && !prismWindow.normalEditPlaybackPlaying) ||
                !videoSurface.mpv || videoSurface.mpv.paused)
                return;
            const at=videoSurface.mpv.position;
            if (prismWindow.previewSelectionPlaying && at >= prismWindow.editEnd-0.025) {
                prismWindow.stopRangePreview();
                return;
            }
            const next=editCuts.nextSourceWhilePlaying(at);
            if (next === -2) {
                prismWindow.stopRangePreview();
            } else if (next >= 0) {
                if (prismWindow.previewSelectionPlaying && next >= prismWindow.editEnd-0.025) {
                    prismWindow.stopRangePreview();
                    return;
                }
                playerController.seek(next);
            }
        }
        function onMediaPathChanged() {
            // A new source makes the prior editing range meaningless.
            if (prismWindow.editMode &&
                videoSurface.mpv.mediaPath !== prismWindow.editSourcePath) {
                prismWindow.previewSelectionPlaying = false;
                prismWindow.normalEditPlaybackPlaying = false;
                playerController.setSpeed(prismWindow.normalPlaybackSpeed);
                prismWindow.restorePlaybackAudio();
                prismWindow.restorePlaybackRotation();
                prismWindow.editMode = false;
                videoThumbnailController.stop();
                toast.show("Video changed. Edit session closed.", false);
            }
        }
    }

    // Window-level shortcuts work even after a timeline button takes
    // focus. Keep S/Delete/Ctrl+Z separate from the normal player keys.
    Shortcut {
        sequence: "S"
        context: Qt.WindowShortcut
        enabled: prismWindow.editMode
        onActivated: prismWindow.splitEditSelection()
    }
    Shortcut {
        sequence: "Delete"
        context: Qt.WindowShortcut
        enabled: prismWindow.editMode
        onActivated: prismWindow.deleteEditSegment()
    }
    Shortcut {
        sequence: "Ctrl+Z"
        context: Qt.WindowShortcut
        enabled: prismWindow.editMode
        onActivated: { prismWindow.stopRangePreview(); editCuts.undo(); }
    }
    Shortcut {
        sequence: "Ctrl+Shift+Z"
        context: Qt.WindowShortcut
        enabled: prismWindow.editMode
        onActivated: { prismWindow.stopRangePreview(); editCuts.redo(); }
    }
    Shortcut {
        sequence: "Ctrl+Y"
        context: Qt.WindowShortcut
        enabled: prismWindow.editMode
        onActivated: { prismWindow.stopRangePreview(); editCuts.redo(); }
    }

    Item {
        id: globalShortcuts
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
        if (event.modifiers !== Qt.NoModifier && event.modifiers !== Qt.ShiftModifier)
            return;

        switch (event.key) {
        case Qt.Key_Space:
            if (prismWindow.editMode)
                prismWindow.toggleNormalEditPlayback();
            else
                playerController.togglePause();
            event.accepted = true;
            break;
        case Qt.Key_Left:
            playerController.skip(event.modifiers & Qt.ShiftModifier ? -30 : -5);
            event.accepted = true;
            break;
        case Qt.Key_Right:
            playerController.skip(event.modifiers & Qt.ShiftModifier ? 30 : 5);
            event.accepted = true;
            break;
        case Qt.Key_Up:
            playerController.setVolume((videoSurface.mpv ? videoSurface.mpv.volume : 0) + 5);
            event.accepted = true;
            break;
        case Qt.Key_Down:
            playerController.setVolume((videoSurface.mpv ? videoSurface.mpv.volume : 0) - 5);
            event.accepted = true;
            break;
        case Qt.Key_F:
            prismWindow.toggleFullscreen();
            event.accepted = true;
            break;
        case Qt.Key_O:
            openFilesDialog.open();
            event.accepted = true;
            break;
        case Qt.Key_S:
            if (!prismWindow.editMode) playerController.takeScreenshot();
            event.accepted = true;
            break;
        case Qt.Key_B:
            playerController.addBookmarkHere();
            event.accepted = true;
            break;
        case Qt.Key_BracketLeft:
            playerController.setSpeed((videoSurface.mpv ? videoSurface.mpv.speed : 1) - 0.1);
            event.accepted = true;
            break;
        case Qt.Key_BracketRight:
            playerController.setSpeed((videoSurface.mpv ? videoSurface.mpv.speed : 1) + 0.1);
            event.accepted = true;
            break;
        case Qt.Key_Escape:
            if (prismWindow.fullscreenMode) {
                prismWindow.toggleFullscreen();
                event.accepted = true;
            }
            break;
        }
        }
    }

    Component.onCompleted: {
        playerController.mpv = Qt.binding(function() { return videoSurface.mpv; });
        globalShortcuts.forceActiveFocus();
    }

    // Windows' "Open with" / double-click-to-open passes the file path
    // as a plain command-line argument. Opening it synchronously in
    // Component.onCompleted ran before the window's OpenGL/FBO render
    // surface had actually been realized, so mpv decoded and played
    // audio correctly but had nothing valid to render into - picture
    // stayed black while audio and the seek bar worked fine. A short
    // deferred start (after the first frame or two) gives the render
    // context time to exist before loadfile fires. File -> Open always
    // happened well after the window was already fully up, which is
    // why that path never showed the bug.
    Timer {
        interval: 200
        running: true
        repeat: false
        onTriggered: {
            const args = Qt.application.arguments;
            if (args.length > 1) {
                playerController.openFiles([args[args.length - 1]]);
            }
        }
    }

    // Qt.FramelessWindowHint removes the native OS resize border along
    // with the title bar, so without this the window could only be
    // resized via the maximize button - there was no way to drag an
    // edge/corner to a custom size at all. Window.startSystemResize()
    // hands off to the OS's own resize behavior (correct cursor,
    // correct snapping), the same mechanism startSystemMove() already
    // uses for dragging via the top bar. Hidden once maximized or
    // fullscreen, where resizing doesn't apply.
    Item {
        anchors.fill: parent
        visible: prismWindow.visibility !== Window.Maximized && !prismWindow.fullscreenMode
        z: 1000

        readonly property int edge: 6

        MouseArea {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.edge
            cursorShape: Qt.SizeHorCursor
            onPressed: prismWindow.startSystemResize(Qt.LeftEdge)
        }
        MouseArea {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.edge
            cursorShape: Qt.SizeHorCursor
            onPressed: prismWindow.startSystemResize(Qt.RightEdge)
        }
        MouseArea {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.edge
            cursorShape: Qt.SizeVerCursor
            onPressed: prismWindow.startSystemResize(Qt.TopEdge)
        }
        MouseArea {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.edge
            cursorShape: Qt.SizeVerCursor
            onPressed: prismWindow.startSystemResize(Qt.BottomEdge)
        }
        MouseArea {
            anchors.left: parent.left
            anchors.top: parent.top
            width: parent.edge * 2
            height: parent.edge * 2
            cursorShape: Qt.SizeFDiagCursor
            onPressed: prismWindow.startSystemResize(Qt.LeftEdge | Qt.TopEdge)
        }
        MouseArea {
            anchors.right: parent.right
            anchors.top: parent.top
            width: parent.edge * 2
            height: parent.edge * 2
            cursorShape: Qt.SizeBDiagCursor
            onPressed: prismWindow.startSystemResize(Qt.RightEdge | Qt.TopEdge)
        }
        MouseArea {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            width: parent.edge * 2
            height: parent.edge * 2
            cursorShape: Qt.SizeBDiagCursor
            onPressed: prismWindow.startSystemResize(Qt.LeftEdge | Qt.BottomEdge)
        }
        MouseArea {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: parent.edge * 2
            height: parent.edge * 2
            cursorShape: Qt.SizeFDiagCursor
            onPressed: prismWindow.startSystemResize(Qt.RightEdge | Qt.BottomEdge)
        }
    }
}
