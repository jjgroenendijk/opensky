// HUD & Interaction > Messages: the seam the sidebar reads and the readout lines.

import Foundation
import OpenSkyScriptingInterface

nonisolated public struct MessageControlSnapshot: Equatable, Sendable {
    public var isAvailable = false
    public var messageNames: [String] = []
    public var visible: [String] = []
    public var waitingCount = 0
    public var postedCount = 0
    public var droppedCount = 0
    public var helpText: String?
    /// One line per help event: its count and whether it is done.
    public var helpLines: [String] = []
    public var openBox: String?
    public var queuedBoxes = 0
    public var lastAnswer: String?
    public var lastOutcome: String?

    public init() {}
}

public protocol MessageControlProviding: AnyObject {
    var messageSnapshot: MessageControlSnapshot { get }
    func showMessage(editorID: String, asBox: Bool)
    func resetHelpMessages()
}

extension MessageCoordinator {
    public func snapshot(lastOutcome: String?) -> MessageControlSnapshot {
        var snapshot = MessageControlSnapshot()
        snapshot.isAvailable = world != nil
        snapshot.messageNames = world?.messageEditorIDs ?? []
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
        snapshot.lastAnswer = lastAnswer.map { "button \($0.buttonIndex)" }
        snapshot.lastOutcome = lastOutcome
        return snapshot
    }
}

nonisolated public enum MessageReadout {
    public static func text(for snapshot: MessageControlSnapshot) -> String {
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
        if let answer = snapshot.lastAnswer {
            lines.append("Last answer: \(answer)")
        }
        if let outcome = snapshot.lastOutcome {
            lines.append("Last: \(outcome)")
        }
        return lines.joined(separator: "\n")
    }
}

/// Lets the app's provider stand in for its coordinator, one line to conform.
public protocol MessageControlForwarding: MessageControlProviding {
    var messages: MessageCoordinator { get }
}

extension MessageControlForwarding {
    public var messageSnapshot: MessageControlSnapshot {
        messages.snapshot(lastOutcome: messages.lastPanelOutcome)
    }

    public func showMessage(editorID: String, asBox: Bool) {
        messages.lastPanelOutcome = messages.show(editorID: editorID, asBox: asBox)
    }

    public func resetHelpMessages() {
        messages.resetAllHelpMessages()
        messages.lastPanelOutcome = "Reset every help message"
    }
}
