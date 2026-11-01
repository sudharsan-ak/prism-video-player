import QtQuick

// Session-only, non-destructive edit decision list.
// All boundaries refer to the unchanged original source media.
// Collapsed removed segments occupy zero *visual* width, whereas all
// removed segments occupy zero *playback/export* time.
QtObject {
    id: root
    property var segments: []
    property int selectedId: -1
    property int nextId: 1
    property var undoStack: []
    property var redoStack: []
    property real sourceDuration: 0
    property string warning: ""
    readonly property bool canUndo: undoStack.length > 0
    readonly property bool canRedo: redoStack.length > 0
    readonly property bool hasCuts: segments.length > 1 ||
        segments.some(s => s.removed)
    readonly property var displaySegments: {
        let v = 0, kept = 0;
        return segments.map(s => {
            const n = Object.assign({}, s, {
                visualStart: v, keptStart: kept
            });
            if (!s.collapsed) v += s.end - s.start;
            if (!s.removed) kept += s.end - s.start;
            n.visualEnd = v;
            n.keptEnd = kept;
            return n;
        });
    }
    readonly property real visualDuration: displaySegments.length
        ? displaySegments[displaySegments.length - 1].visualEnd : 0
    readonly property real keptDuration: displaySegments.length
        ? displaySegments[displaySegments.length - 1].keptEnd : 0
    readonly property var keptRanges: segments.filter(s => !s.removed)
        .map(s => ({ start: s.start, end: s.end }))
    readonly property var selected: segments.find(s => s.id === selectedId) || null

    function copy(a) { return a.map(s => Object.assign({}, s)); }
    function snapshot() {
        return { segments: copy(segments), selectedId: selectedId, nextId: nextId };
    }
    function apply(s) {
        segments = copy(s.segments);
        selectedId = s.selectedId;
        nextId = s.nextId;
        warning = "";
    }
    function commit(next, selected, nextNumber) {
        undoStack = undoStack.concat([snapshot()]).slice(-100);
        redoStack = [];
        segments = next;
        selectedId = selected;
        nextId = nextNumber;
        warning = "";
    }
    function reset(duration) {
        sourceDuration = Math.max(0, duration);
        segments = sourceDuration > 0 ? [{
            id: 1, start: 0, end: sourceDuration,
            removed: false, collapsed: false
        }] : [];
        nextId = 2;
        selectedId = sourceDuration > 0 ? 1 : -1;
        undoStack = [];
        redoStack = [];
        warning = "";
    }
    function splitSelection(start, end) {
        const a = Math.max(0, Number(start)), b = Math.min(sourceDuration, Number(end));
        if (!isFinite(a) || !isFinite(b) || b - a < 0.05) {
            warning = "Select at least 0.05 seconds with IN/OUT.";
            return false;
        }
        // Split a single retained source segment at both selection edges.
        // Never join across a pre-existing split or an excluded gap.
        const index = segments.findIndex(s => !s.removed &&
            a >= s.start - 0.0001 && b <= s.end + 0.0001);
        if (index < 0) {
            warning = "Choose IN and OUT inside one retained segment.";
            return false;
        }
        const s = segments[index], before = a > s.start + 0.001,
              after = b < s.end - 0.001;
        if (!before && !after) {
            selectedId = s.id;
            warning = "This portion is already its own segment.";
            return false;
        }
        let id = nextId, middle = s.id;
        const parts = [];
        if (before) parts.push({ id: id++, start: s.start, end: a,
                                removed: false, collapsed: false });
        parts.push({ id: middle, start: before ? a : s.start,
                     end: after ? b : s.end, removed: false, collapsed: false });
        if (after) parts.push({ id: id++, start: b, end: s.end,
                               removed: false, collapsed: false });
        commit(segments.slice(0,index).concat(parts,segments.slice(index+1)), middle, id);
        return true;
    }
    function select(id) { if (segments.some(s => s.id === id)) selectedId = id; }
    function softDelete() {
        if (!selected || selected.removed) return false;
        if (keptRanges.length <= 1) {
            warning = "Keep at least one playable segment.";
            return false;
        }
        commit(segments.map(s => s.id === selectedId ?
               Object.assign({},s,{removed:true,collapsed:false}) : s), selectedId, nextId);
        return true;
    }
    function removeGap() {
        if (!selected || !selected.removed || selected.collapsed) return false;
        commit(segments.map(s => s.id === selectedId ?
               Object.assign({},s,{collapsed:true}) : s), selectedId, nextId);
        return true;
    }
    function restore() {
        if (!selected || !selected.removed) return false;
        commit(segments.map(s => s.id === selectedId ?
               Object.assign({},s,{removed:false,collapsed:false}) : s), selectedId, nextId);
        return true;
    }
    function undo() {
        if (!canUndo) return;
        const last = undoStack[undoStack.length - 1];
        redoStack = redoStack.concat([snapshot()]);
        undoStack = undoStack.slice(0,-1);
        apply(last);
    }
    function redo() {
        if (!canRedo) return;
        const last = redoStack[redoStack.length-1];
        undoStack = undoStack.concat([snapshot()]);
        redoStack = redoStack.slice(0,-1);
        apply(last);
    }
    function sourceToVisual(t) {
        const sec = Math.max(0,Math.min(sourceDuration,t));
        for (const s of displaySegments) {
            if (sec <= s.end + 0.00001)
                return s.visualStart + (s.collapsed ? 0 :
                    Math.max(0,Math.min(s.end-s.start,sec-s.start)));
        }
        return visualDuration;
    }
    function visualToSource(t) {
        const sec = Math.max(0,Math.min(visualDuration,t));
        for (const s of displaySegments) {
            if (s.collapsed) continue;
            if (sec < s.visualEnd - 0.00001 || s === displaySegments[displaySegments.length-1]) {
                if (s.removed) {
                    const next = displaySegments.find(n => !n.removed && n.start >= s.end - 0.00001);
                    return next ? next.start : (keptRanges.length
                        ? keptRanges[keptRanges.length-1].end : s.start);
                }
                return s.start+Math.max(0,Math.min(s.end-s.start,sec-s.visualStart));
            }
        }
        return keptRanges.length ? keptRanges[keptRanges.length-1].end : 0;
    }
    function sourceToKept(t) {
        let elapsed = 0;
        for (const s of segments) {
            if (s.removed) continue;
            if (t <= s.start) return elapsed;
            if (t < s.end) return elapsed + t-s.start;
            elapsed += s.end-s.start;
        }
        return elapsed;
    }
    function keptToSource(t) {
        let remain = Math.max(0,Math.min(keptDuration,t));
        for (const s of segments) {
            if (s.removed) continue;
            const d = s.end-s.start;
            if (remain < d-0.00001) return s.start+remain;
            remain -= d;
        }
        const r = keptRanges;
        return r.length ? r[r.length-1].end : 0;
    }
    function nextKeptStart(time) {
        const s = segments.find(x => !x.removed && x.start > time+0.0001);
        return s ? s.start : -1;
    }
    function nextSourceWhilePlaying(t) {
        for (const s of segments) {
            if (s.removed) continue;
            if (t >= s.start-0.015 && t < s.end-0.02) return -1;
            if (s.start >= t-0.03) return s.start;
        }
        return -2; // end of the edited result
    }
}
