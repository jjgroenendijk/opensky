// Main-app dialogue seam (issue #205, roadmap item 17.3, scope point 7). Keeps
// the dialogue panel independent of `GameViewController` while exposing the
// Talk target, the menu's menu-stack presence and pause policy, the topics on
// offer, and why a topic that is not on offer lost.
//
// The seam mirrors `JournalControlProviding`: the panel reads one snapshot per
// refresh and calls one mutation entry point per user action. It never sees
// `DialogueRuntime`, `MenuStack` or `SWFMovieRuntime` directly, so the engine
// keeps ownership of main-actor state.
//
// The condition-trace readout is #426's `DialogueSelection` reduced to lines
// rather than a second evaluation: item 17.8 has to explain why a line the
// player expected did not appear, and selection already keeps every outcome it
// computed for exactly that. Reducing it here rather than in the panel is what
// lets the wording be unit tested without a window.
//
// Documented in docs/engine/dialogue-menu.md.

import Foundation

/// One topic as the panel lists it.
nonisolated struct DialogueTopicRow: Equatable, Sendable {
    let topic: FormID
    /// The INFO that won the topic, which is what choosing the row delivers.
    let info: FormID
    /// What the row reads in the menu.
    let text: String
    /// Whether the winning response ends the conversation.
    let endsConversation: Bool
}

/// One topic that offered nothing, with the reason its responses lost.
nonisolated struct DialogueRejectionRow: Equatable, Sendable {
    let topic: FormID
    /// One phrase per considered response, in evaluation order: the reason it
    /// was not chosen, worded the way `DialogueRejection` states it.
    let reasons: [String]
}

/// Everything the dialogue readouts show, captured in one value.
nonisolated struct DialogueControlSnapshot: Equatable {
    /// Rows a snapshot carries. A speaker can offer more topics than a readout
    /// is worth, and the panel states how many it dropped rather than growing
    /// without bound.
    static let rowLimit = 12

    static let empty = DialogueControlSnapshot(
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
    let hasDialogueIndex: Bool
    let topicCount: Int
    let infoCount: Int

    // MARK: Talk target

    /// The actor the crosshair is on, when it is on one. Nil means the use key
    /// would not start a conversation.
    let targetName: String?
    let targetKey: ReferenceKey?

    // MARK: Conversation

    /// Who the open conversation is with, empty when none is open.
    let speaker: String
    let isOpen: Bool
    /// Menu-stack identifiers currently open, top last. Proves the menu drives
    /// the engine's own stack rather than a private flag.
    let openMenus: [String]
    /// The engine's pause gate right now. The point of the whole per-menu
    /// policy is that this stays false with the dialogue menu open, so the
    /// readout shows it rather than assuming it.
    let worldSimPaused: Bool
    /// `DialogueMenuModel.State`, or `closed`.
    let state: String
    let rows: [DialogueTopicRow]
    let droppedRowCount: Int
    let selectedIndex: Int
    /// The line being said, nil when none is.
    let subtitle: String?

    // MARK: Why a topic is missing

    let rejections: [DialogueRejectionRow]
    /// Condition calls the evaluator could not answer while selecting, which is
    /// the number that says how much of the trace is real.
    let unresolvedConditionCount: Int
    /// Result of the last panel control, worded for the readout.
    let lastOutcome: String?

    // MARK: Movie

    let movieLoaded: Bool
    let movieError: String?
    /// Rows the movie's own topic list holds, read back out of it.
    let movieTopicRows: Int
    let movieSelectedIndex: Int?
    /// Text the movie's own subtitle field holds.
    let movieSubtitle: String?
    /// The movie's own `eMenuState`, which the engine writes and reads back.
    let movieMenuState: Int?
    let movieDiagnostics: DialogueMenuDiagnostics
}

/// Live-renderer seam for the dialogue section.
///
/// `refocusGameView()` is deliberately absent: `HUDControlProviding` already
/// declares it and the panel reaches it through the composed
/// `WorldControlProviders`.
@MainActor
protocol DialogueControlProviding: AnyObject {
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
