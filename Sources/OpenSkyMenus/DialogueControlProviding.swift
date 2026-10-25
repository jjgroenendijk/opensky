// Main-app dialogue seam: the Talk target, the menu's stack presence and pause
// policy, the topics on offer, and why a missing topic lost. The readout reads
// one snapshot and calls one mutation per action, like
// `JournalControlProviding`. The condition trace reduces `DialogueSelection`
// to lines here, so the wording is testable without a window
// (docs/engine/dialogue-menu.md).

import Foundation
import OpenSkyFormatsESM

/// One topic as the readout lists it.
nonisolated public struct DialogueTopicRow: Equatable, Sendable {
    /// What the row reads in the menu.
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

/// One topic that offered nothing, with the reason its responses lost.
nonisolated public struct DialogueRejectionRow: Equatable, Sendable {
    public let topic: FormID
    /// One phrase per considered response, in evaluation order: the reason it
    /// was not chosen, worded the way `DialogueRejection` states it.
    public let reasons: [String]

    public init(topic: FormID, reasons: [String]) {
        self.topic = topic
        self.reasons = reasons
    }
}

/// Everything the dialogue readouts show, captured in one value.
nonisolated public struct DialogueControlSnapshot: Equatable, Sendable {
    /// Rows a snapshot carries. A speaker can offer more topics than a readout
    /// is worth, and the readout states how many it dropped rather than growing
    /// without bound.
    public static let rowLimit = 12

    public static let empty = DialogueControlSnapshot(
        isOpen: false,
        openMenus: [],
        worldSimPaused: false,
        rows: [],
        selectedIndex: -1,
        subtitle: nil,
        rejections: [],
        unresolvedConditionCount: 0
    )

    // MARK: Records

    // MARK: Talk target

    // MARK: Conversation

    public let isOpen: Bool
    /// Menu-stack identifiers currently open, top last. Proves the menu drives
    /// the engine's own stack rather than a private flag.
    public let openMenus: [String]
    /// The engine's pause gate right now. The point of the whole per-menu
    /// policy is that this stays false with the dialogue menu open, so the
    /// readout shows it rather than assuming it.
    public let worldSimPaused: Bool
    public let rows: [DialogueTopicRow]
    public let selectedIndex: Int
    /// The line being said, nil when none is.
    public let subtitle: String?

    // MARK: Why a topic is missing

    public let rejections: [DialogueRejectionRow]
    /// Condition calls the evaluator could not answer while selecting, which is
    /// the number that says how much of the trace is real.
    public let unresolvedConditionCount: Int

    // MARK: Movie

    public init(
        isOpen: Bool,
        openMenus: [String],
        worldSimPaused: Bool,
        rows: [DialogueTopicRow],
        selectedIndex: Int,
        subtitle: String?,
        rejections: [DialogueRejectionRow],
        unresolvedConditionCount: Int
    ) {
        self.isOpen = isOpen
        self.openMenus = openMenus
        self.worldSimPaused = worldSimPaused
        self.rows = rows
        self.selectedIndex = selectedIndex
        self.subtitle = subtitle
        self.rejections = rejections
        self.unresolvedConditionCount = unresolvedConditionCount
    }
}
