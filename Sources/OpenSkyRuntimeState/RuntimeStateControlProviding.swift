// The runtime state snapshot. A reader takes one `RuntimeStateSnapshot` per refresh
// and calls one mutation per action; it never sees `WorldStateStore` or `CellStreamer`.
// See docs/engine/runtime-state.md.

import simd

/// Which reference a mutation applies to: the one in view, or a typed FormID. The text is
/// raw, because only the provider has the plugin context to parse it.
nonisolated public enum RuntimeStateTargetSelector: Equatable, Sendable {
    /// The reference the interaction ray currently targets, if any.
    case currentTarget
    /// A FormID as typed by the user, in hexadecimal with or without a `0x`
    /// prefix.
    case formID(String)
}

/// Fixed magnitudes the mutations use, so the label and the
/// engine implementation cannot drift apart.
nonisolated public enum RuntimeStateTuning: Sendable {
    /// Offset applied by `nudgeReferenceTransform(target:)`, in game units
    /// (roughly 0.014 metres each), along world +X. Ten units is large enough
    /// to be visible on any object the player can look at and small enough
    /// that it never moves a reference out of its cell.
    public static let transformNudge = SIMD3<Float>(10, 0, 0)
}

/// Everything the runtime-state readout shows, captured in one value.
///
/// A struct rather than a set of individual protocol properties: the readout
/// refreshes all of these together, and a single snapshot makes the readout a
/// pure function of one engine sample instead of several taken at slightly
/// different times.
nonisolated public struct RuntimeStateSnapshot: Equatable, Sendable {
    /// Journal lines a snapshot carries at most. The readout shows recent
    /// history, not the whole bounded window, which is thousands of entries.
    public static let journalTailLimit = 8

    /// Runtime references retained by the currently resident cell scenes.
    public let residentReferenceCount: Int
    /// References in the store deviating from plugin data.
    public let dirtyReferenceCount: Int
    /// Globals carrying a runtime override.
    public let overriddenGlobalCount: Int
    /// Preformatted journal lines, most recent last, at most
    /// `journalTailLimit` of them. Preformatted because the readout must not
    /// have to know how to render a `WorldStateJournalEntry`.
    public let journalTail: [String]
    /// Journal entries dropped because the retained window filled up.
    public let droppedJournalEntryCount: Int
    /// Sequence number the next journalled mutation will carry.
    public let nextJournalSequence: UInt64
    /// `ReferenceKey.description` of the current interaction target, or nil
    /// when nothing is targeted. A `String` rather than a `ReferenceKey` so the
    /// readout can display it without formatting logic; `.currentTarget` is how
    /// it mutates that reference.
    public let currentTargetDescription: String?

    /// Explicit, so `overriddenGlobalCount` can default to zero.
    public init(
        residentReferenceCount: Int,
        dirtyReferenceCount: Int,
        journalTail: [String],
        droppedJournalEntryCount: Int,
        nextJournalSequence: UInt64,
        currentTargetDescription: String?,
        overriddenGlobalCount: Int = 0
    ) {
        self.residentReferenceCount = residentReferenceCount
        self.dirtyReferenceCount = dirtyReferenceCount
        self.journalTail = journalTail
        self.droppedJournalEntryCount = droppedJournalEntryCount
        self.nextJournalSequence = nextJournalSequence
        self.currentTargetDescription = currentTargetDescription
        self.overriddenGlobalCount = overriddenGlobalCount
    }
}

/// Result of the most recent save or load the provider attempted.
///
/// The failure case carries the typed error's description verbatim rather than
/// a friendlier paraphrase: a save that fails is a data-loss event, and the
/// exact `OpenSkySaveError` or `OpenSkySaveStoreError` text is what makes it
/// diagnosable from a screenshot.
nonisolated public enum RuntimeStateSaveOutcome: Equatable, Sendable {
    /// Nothing has been saved or loaded this session.
    case none
    /// The file work for `operation` ("save" or "load") has not finished yet.
    case running(operation: String, slot: String)
    case saved(slot: String)
    case loaded(slot: String)
    /// `operation` names what was attempted ("save" or "load") and `message`
    /// is the thrown error's description, unaltered.
    case failed(operation: String, message: String)
}
