// Developer > UI Lab SWF runtime readout (M8.3.3): the device-free half of the
// AS2 runtime verification surface.
//
// `SWFLabRuntimeSnapshot` is one flat, Equatable copy of everything the panel
// shows — movie state, the `GameDelegate` invoke log, and the interpreter's op
// tally — taken from a live `SWFMovieRuntime` on the main thread between
// frames. The section never reaches into the runtime while it draws, and the
// snapshot compares equal, so a readout can be asserted as a value.
//
// The formatting sits beside it as pure functions for the same reason the
// M8.2.5 readout does: the exact wording is unit-tested without AppKit, without
// a GPU, and without a game install.
//
// The op tally is not a debug aid. The milestone's stated risk-management
// mechanism is that an unimplemented opcode or an unknown host API degrades to
// a logged no-op plus a tally entry, so showing the tally is how a user sees
// what a menu could not do (docs/decisions/swf-as2-scope.md).

import Foundation

/// What a running movie's AS2 runtime looks like from outside, at one instant.
/// Every field defaults, so a test can build the one case it is asserting.
nonisolated struct SWFLabRuntimeSnapshot: Equatable {
    /// True once the bring-up sequence ran (`DoInitAction`, frame 1, its
    /// `DoAction`).
    var isStarted = false
    /// Explicit ticks applied since bring-up. Never a time source.
    var tickCount = 0
    /// Live display nodes in the whole tree, including the root.
    var nodeCount = 0
    var rootChildCount = 0
    /// Zero-based playhead of the root timeline; -1 until frame 1 executes.
    var currentFrame = -1
    var frameCount = 0
    /// Slash path of the `Selection.setFocus` target, or nil when unfocused.
    var focusPath: String?
    /// Instantiations refused because the tree hit its node cap.
    var droppedInstantiations = 0
    /// Frame `DoAction` blocks skipped by the goto re-entry guard.
    var droppedFrameActions = 0
    var timerCount = 0
    var droppedTimers = 0
    var pointerEvents = 0
    var keyEvents = 0
    /// `Key.getCode()`: the most recent injected key.
    var lastKeyCode = 0
    /// Callback names the movie registered with `GameDelegate.addCallBack` —
    /// exactly the engine-to-movie calls this menu is prepared for.
    var callbackNames: [String] = []
    var invokeLog = SWFInvokeLog()
    var tally = AS2Tally()
    var trace = AS2TraceLog()
}

nonisolated extension SWFLabRuntimeSnapshot {
    /// Reads a live runtime. Main thread, between frames — the same contract
    /// every other renderer seam runs under.
    init(runtime: SWFMovieRuntime) {
        self.init(
            isStarted: runtime.isStarted,
            tickCount: runtime.tickCount,
            nodeCount: runtime.nodeCount,
            rootChildCount: runtime.root.childCount,
            currentFrame: runtime.root.currentFrame,
            frameCount: runtime.root.frameCount,
            focusPath: runtime.focusTarget?.targetPath,
            droppedInstantiations: runtime.droppedInstantiations,
            droppedFrameActions: runtime.droppedFrameActions,
            timerCount: runtime.timers.count,
            droppedTimers: runtime.timers.dropped,
            pointerEvents: runtime.input.pointerEvents,
            keyEvents: runtime.input.keyEvents,
            lastKeyCode: runtime.input.lastKeyCode,
            callbackNames: runtime.movieCallbackNames,
            invokeLog: runtime.invokeLog,
            tally: runtime.tally,
            trace: runtime.traceLog
        )
    }
}

nonisolated extension SWFLabReadout {
    /// Invoke-log entries the readout shows. The header still reports the
    /// totals, so a clipped list never hides how much it stopped showing.
    static let shownInvokeEntries = 6
    /// Ranked names shown per tally line.
    static let shownRankedNames = 3

    /// Movie state: is the runtime up, how far has it been ticked, how big is
    /// the tree, and what did it have to drop.
    static func runtimeText(for snapshot: SWFLabControlSnapshot) -> String {
        guard let runtime = snapshot.runtime else {
            return snapshot.selectedPath == nil
                ? "Runtime: no movie selected"
                : "Runtime: stopped · Start runs the movie's ActionScript"
        }
        let lines = [
            "Runtime: \(runtime.isStarted ? "running" : "loaded") · "
                + "tick \(runtime.tickCount) · "
                + "frame \(runtime.currentFrame)/\(runtime.frameCount)",
            "Nodes: \(runtime.nodeCount) · root children \(runtime.rootChildCount) · "
                + "timers \(runtime.timerCount)",
            "Focus: \(runtime.focusPath ?? "none")",
            "Input: pointer \(runtime.pointerEvents) · key \(runtime.keyEvents) · "
                + "last key \(runtime.lastKeyCode)",
            "Dropped: nodes \(runtime.droppedInstantiations) · "
                + "frame actions \(runtime.droppedFrameActions) · "
                + "timers \(runtime.droppedTimers)"
        ]
        return lines.joined(separator: "\n")
    }

    /// Both directions of the `GameDelegate` bridge: what the menu is prepared
    /// to be called with, and what actually crossed.
    static func invokeText(for snapshot: SWFLabControlSnapshot) -> String {
        guard let runtime = snapshot.runtime else {
            return "Invokes: runtime not started"
        }
        let log = runtime.invokeLog
        var lines = [
            "Invokes: \(log.total) total · \(log.unhandled) unhandled · "
                + "\(log.dropped) dropped",
            "Callbacks: " + nameList(runtime.callbackNames)
        ]
        let shown = log.entries.suffix(shownInvokeEntries)
        if shown.isEmpty {
            lines.append("Recent: none")
        } else {
            lines.append("Recent (\(shown.count) of \(log.total)):")
            lines.append(contentsOf: shown.map(entryLine))
        }
        return lines.joined(separator: "\n")
    }

    /// The interpreter's op tally — what ran, what faulted, and what was not
    /// implemented — plus whatever the movie traced.
    static func tallyText(for snapshot: SWFLabControlSnapshot) -> String {
        guard let runtime = snapshot.runtime else {
            return "Ops: runtime not started"
        }
        let tally = runtime.tally
        let lines = [
            "Ops: \(tally.actionsExecuted) actions · \(tally.blocksExecuted) blocks · "
                + "\(tally.callsPerformed) calls",
            "Faults: \(tally.faultTotal)\(faultKinds(tally)) · "
                + "underflows \(tally.stackUnderflows)",
            "Unimplemented: "
                + rankedList(tally.unimplementedTotal, tally.rankedUnimplemented),
            "Missing: " + rankedList(tally.missingTotal, tally.rankedMissing),
            traceLine(runtime.trace)
        ]
        return lines.joined(separator: "\n")
    }

    private static func entryLine(_ entry: SWFInvokeEntry) -> String {
        let suffix = entry.isHandled ? "" : " [unhandled]"
        return "\(entry.direction.rawValue) \(entry.name)(\(entry.arguments)) "
            + "-> \(entry.result)\(suffix)"
    }

    private static func nameList(_ names: [String]) -> String {
        guard !names.isEmpty else {
            return "none"
        }
        let head = names.prefix(shownRankedNames).joined(separator: ", ")
        return names.count > shownRankedNames
            ? "\(names.count) (\(head), …)"
            : head
    }

    /// `12 (callDepthExceeded 8, invalidJump 4)`. Faults are kept verbatim up to
    /// a cap while `faultTotal` keeps counting, so the count and the kinds can
    /// legitimately disagree.
    private static func faultKinds(_ tally: AS2Tally) -> String {
        guard !tally.faults.isEmpty else {
            return ""
        }
        var counts: [String: Int] = [:]
        for fault in tally.faults {
            counts[fault.kind, default: 0] += 1
        }
        let top = counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(shownRankedNames)
            .map { "\($0.key) \($0.value)" }
        return " (" + top.joined(separator: ", ") + ")"
    }

    private static func rankedList(
        _ total: Int,
        _ entries: [(name: String, count: Int)]
    ) -> String {
        guard total > 0 else {
            return "none"
        }
        let head = entries
            .prefix(shownRankedNames)
            .map { "\($0.name) \($0.count)" }
            .joined(separator: ", ")
        return head.isEmpty ? "\(total)" : "\(total) (\(head))"
    }

    private static func traceLine(_ trace: AS2TraceLog) -> String {
        guard let last = trace.messages.last else {
            return "Trace: none"
        }
        return "Trace: \(trace.total) · dropped \(trace.dropped) · last \"\(last)\""
    }
}
