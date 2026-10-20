// Dialogue state as a world-state component: one INFO's said-state, keyed by
// the INFO's `ReferenceKey`. Say Once is per speaker: "a different actor that
// qualifies may say it" (<https://ck.uesp.net/wiki/Topic_Info>).
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
    /// `GameDaysPassed` when each speaker last said the response, kept for a response
    /// with a reset time or Say Once. A Say Once line said without a clock stores day 0.
    public private(set) var saidDays: [ReferenceKey: Double]

    /// The state an INFO has before anything says it, which is the baseline of
    /// every INFO in every plugin: a response nothing has spoken.
    public static let unsaid = DialogueRuntimeState()

    public static var componentKind: WorldStateComponentKind {
        .dialogue
    }

    public init(saidCount: UInt32 = 0, saidDays: [ReferenceKey: Double] = [:]) {
        self.saidCount = saidCount
        self.saidDays = saidDays
    }

    /// Whether this response has ever been said, by anyone.
    public var hasBeenSaid: Bool {
        saidCount > 0
    }

    /// The Say Once test. A count with no speaker on record, as an older save has,
    /// counts for every speaker.
    public func hasBeenSaid(by speaker: ReferenceKey) -> Bool {
        saidDays[speaker] != nil || (saidCount > 0 && saidDays.isEmpty)
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
        DialogueRuntimeState(
            saidCount: saidCount == .max ? .max : saidCount + 1, saidDays: saidDays
        )
    }

    /// `said()`, with the day `speaker` said it. A nil day records no time.
    public func said(by speaker: ReferenceKey, onDay day: Double?) -> Self {
        var state = said()
        if let day {
            state.saidDays[speaker] = day
        }
        return state
    }

    /// Whether `speaker` may say a line with `resetHours` again on `day`. Without a
    /// said time or a clock nothing can be measured, so the line is not held back.
    public func hasReset(resetHours: Float, speaker: ReferenceKey, onDay day: Double?) -> Bool {
        guard resetHours > 0, let last = saidDays[speaker], let day else { return true }
        return (day - last) * 24 >= Double(resetHours)
    }
}

nonisolated extension WorldStateComponentKind {
    /// One dialogue response's said-state. Like `quest` it modifies no placement:
    /// it is keyed by an INFO base record's `ReferenceKey`, because a response is
    /// not placed anywhere and belongs to no cell.
    public static let dialogue = Self(rawValue: "dialogue", order: 11, affectsCellBuild: false)
}
