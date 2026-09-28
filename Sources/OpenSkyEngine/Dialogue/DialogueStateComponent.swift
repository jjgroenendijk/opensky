// Dialogue runtime state as a world-state component (issue #426, roadmap item
// 17.2): the value type that holds one INFO's said-state once a speaker has
// actually said it.
//
// It lives here rather than in `WorldStateComponents.swift` for the reason
// `QuestRuntimeState` does: the type carries behaviour of its own — the
// documented say-once rule and the reset interval — rather than being a plain
// field bag. Only the `WorldStateComponentKind` case and the
// `WorldStateComponentValue` case sit with the rest, so every store operation
// stays generic over the protocol.
//
// An INFO is a base record rather than a placed reference, which the store does
// not care about: state is keyed by the INFO record's session-stable
// `ReferenceKey`, exactly as `QuestRuntimeState` is keyed by the QUST record's,
// so journalling, snapshot ordering and the mutation callbacks apply unchanged.
//
// ## Why said-state is per INFO and not per speaker
//
// The Creation Kit's Response Data window documents the flag as a property of
// the *response*, not of a conversation: "Say Once: If checked, this info will
// only be said once. Once said, it will never be said again."
// (<https://ck.uesp.net/wiki/Dialogue_Views>, Response Data). Nothing in that
// sentence is scoped to a speaker, and shared INFOs are reachable from several
// speakers through DNAM, so a per-speaker table would let the same line be said
// once by each of them. One counter per INFO record is what the documented rule
// describes.
//
// ## What the probe showed is persistent, and what is not
//
// Branch progression is *not* stored here. A vanilla sweep of Skyrim.esm found
// zero INFOs carrying a PNAM previous-info link and 4,294 carrying TCLT topic
// links, so the flow from one line to the next is a pure function of the chosen
// INFO's own record plus said-state — there is no separate cursor to persist.
// See docs/engine/dialogue.md.
//
// Documented in docs/engine/runtime-state.md and docs/engine/dialogue.md.

import Foundation

/// Failures the dialogue layer reports.
///
/// Every one is a caller mistake rather than malformed input, which is why they
/// are distinct from `ESMError`, and every one is thrown rather than clamped:
/// choosing an INFO no loaded plugin declares is a bug that a silent no-op
/// would hide behind a conversation that simply never advances.
nonisolated enum DialogueError: Error, Equatable {
    /// No loaded plugin declares an INFO with this FormID.
    case unknownInfo(FormID)
    /// The INFO record exists but its FormID does not resolve to a
    /// session-stable `ReferenceKey`, so there is nowhere to key said-state.
    case unresolvedInfoKey(FormID)
    /// No loaded plugin declares a DIAL with this FormID.
    case unknownTopic(FormID)
}

/// Everything the runtime records about one INFO.
nonisolated struct DialogueRuntimeState: WorldStateComponent {
    /// How often this response has been said. A counter rather than a flag
    /// because the say-once rule needs "ever said" while a repeatable line
    /// still benefits from an honest count in the trace readout, and because a
    /// counter costs the same four bytes a flag would have been padded to.
    private(set) var saidCount: UInt32

    /// The state an INFO has before anything says it, which is the baseline of
    /// every INFO in every plugin: a response nothing has spoken.
    static let unsaid = DialogueRuntimeState()

    static var componentKind: WorldStateComponentKind {
        .dialogue
    }

    var erased: WorldStateComponentValue {
        .dialogue(self)
    }

    init(saidCount: UInt32 = 0) {
        self.saidCount = saidCount
    }

    init?(erased: WorldStateComponentValue) {
        guard case let .dialogue(value) = erased else { return nil }
        self = value
    }

    /// The state every INFO has before anything touches it. Unlike a quest's,
    /// this baseline reads nothing off the record: an INFO carries no authored
    /// "already said" bit, so the baseline is the same for all of them and the
    /// parameter-free `unsaid` is it.
    static func baseline(for _: TopicInfo) -> DialogueRuntimeState {
        .unsaid
    }

    /// Whether this response has ever been said, which is what the say-once
    /// rule tests.
    var hasBeenSaid: Bool {
        saidCount > 0
    }

    /// True when nothing has said this response, which is the state that must
    /// never be written: storing it would make two equal worlds compare unequal
    /// and would put an entry in the save for every INFO a session considered.
    var isUntouched: Bool {
        saidCount == 0
    }

    /// True when the state still equals the plugin baseline, which is what
    /// makes a reset back to plugin data meaningful.
    func matchesBaseline(of info: TopicInfo) -> Bool {
        self == Self.baseline(for: info)
    }

    /// This state with one more saying recorded. Saturating rather than
    /// wrapping: a conversation repeated four billion times is not a reason for
    /// a say-once line to become sayable again.
    func said() -> Self {
        DialogueRuntimeState(saidCount: saidCount == .max ? .max : saidCount + 1)
    }
}
