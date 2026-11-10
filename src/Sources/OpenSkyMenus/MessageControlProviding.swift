// Messages: the snapshot and the readout lines.

import Foundation
import OpenSkyMenusInterface
import OpenSkyScriptingInterface

nonisolated struct MessageControlSnapshot: Equatable, Sendable {
    var isAvailable = false
    var visible: [String] = []
    var waitingCount = 0
    var postedCount = 0
    var droppedCount = 0
    var helpText: String?
    /// One line per help event: its count and whether it is done.
    var helpLines: [String] = []
    var openBox: String?
    var queuedBoxes = 0
    /// What draws the open box: the vanilla movie, or the overlay and why.
    var boxDrawing: String?
    var lastAnswer: String?
    var lastOutcome: String?

    init() {}
}

extension MessageCoordinator {
    func snapshot(lastOutcome: String?) -> MessageControlSnapshot {
        var snapshot = MessageControlSnapshot()
        snapshot.isAvailable = world != nil
        snapshot.visible = notifications.visible.map(\.text)
        snapshot.waitingCount = notifications.waiting.count
        snapshot.postedCount = notifications.postedCount
        snapshot.droppedCount = notifications.droppedCount
        snapshot.helpText = help.visibleText
        snapshot.helpLines = help.records.sorted { $0.key < $1.key }.map { event, record in
            "\(event): shown \(record.timesShown)" + (record.isDone ? ", done" : "")
        }
        snapshot.openBox = boxes.current.map { $0.title ?? String($0.text.prefix(40)) }
        snapshot.queuedBoxes = max(0, boxes.queue.count - 1)
        if boxes.isOpen {
            snapshot.boxDrawing = movie.isLoaded ? "movie" : movie.error.map { "overlay, \($0)" }
                ?? "overlay"
        }
        snapshot.lastAnswer = lastAnswer.map { "button \($0.buttonIndex)" }
        snapshot.lastOutcome = lastOutcome
        return snapshot
    }
}

nonisolated enum MessageReadout {
    static func text(for snapshot: MessageControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Messages: no game data" }
        var lines = [
            "Notifications: \(snapshot.visible.count) shown, \(snapshot.waitingCount) waiting",
            "Posted: \(snapshot.postedCount), repeats dropped: \(snapshot.droppedCount)"
        ]
        lines += snapshot.visible.map { "  \($0)" }
        lines.append("Help: \(snapshot.helpText ?? "none")")
        lines += snapshot.helpLines.map { "  \($0)" }
        lines.append("Box: \(snapshot.openBox ?? "none")"
            + (snapshot.queuedBoxes > 0 ? ", \(snapshot.queuedBoxes) waiting" : ""))
        if let drawing = snapshot.boxDrawing {
            lines.append("Box drawn by: \(drawing)")
        }
        if let answer = snapshot.lastAnswer {
            lines.append("Last answer: \(answer)")
        }
        if let outcome = snapshot.lastOutcome {
            lines.append("Last: \(outcome)")
        }
        return lines.joined(separator: "\n")
    }
}
