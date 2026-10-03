// Dialogue state as a world-state component: one INFO's said-state, keyed by
// the INFO's `ReferenceKey`. Per INFO, not per speaker: "Say Once: ... Once
// said, it will never be said again" (<https://ck.uesp.net/wiki/Dialogue_Views>).
// Branch progress is not stored; it follows from the INFO record and said-state.
// See docs/engine/runtime-state.md and docs/engine/dialogue.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

/// Failures the dialogue layer reports.
///
/// Every one is a caller mistake rather than malformed input, which is why they
/// are distinct from `ESMError`, and every one is thrown rather than clamped:
/// choosing an INFO no loaded plugin declares is a bug that a silent no-op
/// would hide behind a conversation that simply never advances.
nonisolated public enum DialogueError: Error, Equatable {
    /// No loaded plugin declares an INFO with this FormID.
    case unknownInfo(FormID)
    /// The INFO record exists but its FormID does not resolve to a
    /// session-stable `ReferenceKey`, so there is nowhere to key said-state.
    case unresolvedInfoKey(FormID)
}

/// Everything the runtime records about one INFO.
nonisolated public struct DialogueRuntimeState: WorldStateComponent, Sendable {
    /// How often this response has been said. A counter rather than a flag
    /// because the say-once rule needs "ever said" while a repeatable line
    /// still benefits from an honest count in the trace readout, and because a
    /// counter costs the same four bytes a flag would have been padded to.
    public private(set) var saidCount: UInt32

    /// The state an INFO has before anything says it, which is the baseline of
    /// every INFO in every plugin: a response nothing has spoken.
    public static let unsaid = DialogueRuntimeState()

    public static var componentKind: WorldStateComponentKind {
        .dialogue
    }

    public init(saidCount: UInt32 = 0) {
        self.saidCount = saidCount
    }

    /// Whether this response has ever been said, which is what the say-once
    /// rule tests.
    public var hasBeenSaid: Bool {
        saidCount > 0
    }

    /// True when nothing has said this response, which is the state that must
    /// never be written: storing it would make two equal worlds compare unequal
    /// and would put an entry in the save for every INFO a session considered.
    public var isUntouched: Bool {
        saidCount == 0
    }

    /// This state with one more saying recorded. Saturating rather than
    /// wrapping: a conversation repeated four billion times is not a reason for
    /// a say-once line to become sayable again.
    public func said() -> Self {
        DialogueRuntimeState(saidCount: saidCount == .max ? .max : saidCount + 1)
    }
}

nonisolated extension WorldStateComponentKind {
    /// One dialogue response's said-state. Like `quest` it modifies no placement:
    /// it is keyed by an INFO base record's `ReferenceKey`, because a response is
    /// not placed anywhere and belongs to no cell.
    public static let dialogue = Self(rawValue: "dialogue", order: 11, affectsCellBuild: false)
}
