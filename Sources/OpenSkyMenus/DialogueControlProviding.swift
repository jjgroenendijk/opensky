// Main-app dialogue seam: the Talk target, the menu's stack presence and pause
// policy, the topics on offer, and why a missing topic lost. The panel reads
// one snapshot and calls one mutation per action, like
// `JournalControlProviding`. The condition trace reduces `DialogueSelection`
// to lines here, so the wording is testable without a window
// (docs/engine/dialogue-menu.md).

import Foundation
import OpenSkyFormatsESM

/// One topic as the panel lists it.
nonisolated public struct DialogueTopicRow: Equatable, Sendable {
    /// The INFO that won the topic, which is what choosing the row delivers.
    public let info: FormID
    /// What the row reads in the menu.
    public let text: String
    /// Whether the winning response ends the conversation.
    public let endsConversation: Bool

    public init(info: FormID, text: String, endsConversation: Bool) {
        self.info = info
        self.text = text
        self.endsConversation = endsConversation
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
    /// is worth, and the panel states how many it dropped rather than growing
    /// without bound.
    public static let rowLimit = 12

    public static let empty = DialogueControlSnapshot(
        hasDialogueIndex: false,
        topicCount: 0,
        infoCount: 0,
        targetName: nil,
        targetKey: nil,
        speaker: "",
        isOpen: false,
        openMenus: [],
        worldSimPaused: false,
        state: "closed",
        rows: [],
        droppedRowCount: 0,
        selectedIndex: -1,
        subtitle: nil,
        rejections: [],
        unresolvedConditionCount: 0,
        lastOutcome: nil,
        movieLoaded: false,
        movieError: nil,
        movieTopicRows: 0,
        movieSelectedIndex: nil,
        movieSubtitle: nil,
        movieMenuState: nil,
        movieDiagnostics: .none
    )

    // MARK: Records

    /// False when the session loaded no plugin, which is the one case the
    /// readout states rather than showing zeros that look like an empty index.
    public let hasDialogueIndex: Bool
    public let topicCount: Int
    public let infoCount: Int

    // MARK: Talk target

    /// The actor the crosshair is on, when it is on one. Nil means the use key
    /// would not start a conversation.
    public let targetName: String?
    public let targetKey: ReferenceKey?

    // MARK: Conversation

    /// Who the open conversation is with, empty when none is open.
    public let speaker: String
    public let isOpen: Bool
    /// Menu-stack identifiers currently open, top last. Proves the menu drives
    /// the engine's own stack rather than a private flag.
    public let openMenus: [String]
    /// The engine's pause gate right now. The point of the whole per-menu
    /// policy is that this stays false with the dialogue menu open, so the
    /// readout shows it rather than assuming it.
    public let worldSimPaused: Bool
    /// `DialogueMenuModel.State`, or `closed`.
    public let state: String
    public let rows: [DialogueTopicRow]
    public let droppedRowCount: Int
    public let selectedIndex: Int
    /// The line being said, nil when none is.
    public let subtitle: String?

    // MARK: Why a topic is missing

    public let rejections: [DialogueRejectionRow]
    /// Condition calls the evaluator could not answer while selecting, which is
    /// the number that says how much of the trace is real.
    public let unresolvedConditionCount: Int
    /// Result of the last panel control, worded for the readout.
    public let lastOutcome: String?

    // MARK: Movie

    public let movieLoaded: Bool
    public let movieError: String?
    /// Rows the movie's own topic list holds, read back out of it.
    public let movieTopicRows: Int
    public let movieSelectedIndex: Int?
    /// Text the movie's own subtitle field holds.
    public let movieSubtitle: String?
    /// The movie's own `eMenuState`, which the engine writes and reads back.
    public let movieMenuState: Int?
    public let movieDiagnostics: DialogueMenuDiagnostics

    public init(
        hasDialogueIndex: Bool,
        topicCount: Int,
        infoCount: Int,
        targetName: String?,
        targetKey: ReferenceKey?,
        speaker: String,
        isOpen: Bool,
        openMenus: [String],
        worldSimPaused: Bool,
        state: String,
        rows: [DialogueTopicRow],
        droppedRowCount: Int,
        selectedIndex: Int,
        subtitle: String?,
        rejections: [DialogueRejectionRow],
        unresolvedConditionCount: Int,
        lastOutcome: String?,
        movieLoaded: Bool,
        movieError: String?,
        movieTopicRows: Int,
        movieSelectedIndex: Int?,
        movieSubtitle: String?,
        movieMenuState: Int?,
        movieDiagnostics: DialogueMenuDiagnostics
    ) {
        self.hasDialogueIndex = hasDialogueIndex
        self.topicCount = topicCount
        self.infoCount = infoCount
        self.targetName = targetName
        self.targetKey = targetKey
        self.speaker = speaker
        self.isOpen = isOpen
        self.openMenus = openMenus
        self.worldSimPaused = worldSimPaused
        self.state = state
        self.rows = rows
        self.droppedRowCount = droppedRowCount
        self.selectedIndex = selectedIndex
        self.subtitle = subtitle
        self.rejections = rejections
        self.unresolvedConditionCount = unresolvedConditionCount
        self.lastOutcome = lastOutcome
        self.movieLoaded = movieLoaded
        self.movieError = movieError
        self.movieTopicRows = movieTopicRows
        self.movieSelectedIndex = movieSelectedIndex
        self.movieSubtitle = movieSubtitle
        self.movieMenuState = movieMenuState
        self.movieDiagnostics = movieDiagnostics
    }
}

/// Live-renderer seam for the dialogue section.
///
/// `refocusGameView()` is deliberately absent: `HUDControlProviding` already
/// declares it and the panel reaches it through the composed
/// `WorldControlProviders`.
@MainActor
public protocol DialogueControlProviding: AnyObject {
    /// One sample of everything the readouts show.
    /// `DialogueControlSnapshot.empty` when the session has no dialogue index.
    var dialogueSnapshot: DialogueControlSnapshot { get }

    /// Starts a conversation with the actor the crosshair is on, which is what
    /// the use key does. Records why it could not when there is no such actor,
    /// rather than doing nothing silently.
    func openDialogue()

    /// Ends the conversation and pops the menu stack. No-op when none is open.
    func closeDialogue()

    /// Routes one menu event through the same path as the live keys, so the
    /// panel buttons and the keyboard cannot diverge.
    func sendDialogueInput(_ event: MenuInputEvent)
}
