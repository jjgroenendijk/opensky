// Runtime world-state seam consumed by the World sidebar (issue #162, roadmap
// item 10.1.5). No AppKit here on purpose: the file compiles into both the app
// and the CLI target, so a protocol added here needs no project-membership
// change.
//
// The seam is deliberately narrow. A panel reads one `RuntimeStateSnapshot`
// per refresh and calls one mutation entry point per user action; it never
// sees `WorldStateStore`, `CellStreamer` or `OpenSkySaveStore` directly, so the
// engine keeps ownership of main-actor state and the panel keeps its
// independence from the live renderer.
//
// Documented in docs/engine/runtime-state.md.

import simd

/// Which reference a sidebar mutation applies to.
///
/// Two selectors exist because the panel offers two ways to name a reference:
/// whatever the player is currently looking at, and a FormID typed into a text
/// field. The FormID case carries the user's raw text rather than a parsed
/// `FormID`, because parsing and reporting a bad entry is the provider's job —
/// the panel has no plugin context to resolve a load-order-relative ID with.
nonisolated enum RuntimeStateTargetSelector: Equatable, Sendable {
    /// The reference the interaction ray currently targets, if any.
    case currentTarget
    /// A FormID as typed by the user, in hexadecimal with or without a `0x`
    /// prefix.
    case formID(String)
}

/// Fixed magnitudes the sidebar mutations use, so the panel label and the
/// engine implementation cannot drift apart.
nonisolated enum RuntimeStateTuning {
    /// Offset applied by `nudgeReferenceTransform(target:)`, in game units
    /// (roughly 0.014 metres each), along world +X. Ten units is large enough
    /// to be visible on any object the player can look at and small enough
    /// that it never moves a reference out of its cell.
    static let transformNudge = SIMD3<Float>(10, 0, 0)
}

/// Everything the runtime-state readout shows, captured in one value.
///
/// A struct rather than a set of individual protocol properties: the panel
/// refreshes all of these together, and a single snapshot makes the readout a
/// pure function of one engine sample instead of several taken at slightly
/// different times.
nonisolated struct RuntimeStateSnapshot: Equatable {
    /// Journal lines a snapshot carries at most. The panel shows recent
    /// history, not the whole bounded window, which is thousands of entries.
    static let journalTailLimit = 8

    static let empty = RuntimeStateSnapshot(
        residentReferenceCount: 0,
        dirtyReferenceCount: 0,
        journalTail: [],
        droppedJournalEntryCount: 0,
        nextJournalSequence: 1,
        currentTargetDescription: nil
    )

    /// Runtime references retained by the currently resident cell scenes.
    let residentReferenceCount: Int
    /// References in the store deviating from plugin data.
    let dirtyReferenceCount: Int
    /// Preformatted journal lines, most recent last, at most
    /// `journalTailLimit` of them. Preformatted because the panel must not
    /// have to know how to render a `WorldStateJournalEntry`.
    let journalTail: [String]
    /// Journal entries dropped because the retained window filled up.
    let droppedJournalEntryCount: Int
    /// Sequence number the next journalled mutation will carry.
    let nextJournalSequence: UInt64
    /// `ReferenceKey.description` of the current interaction target, or nil
    /// when nothing is targeted. A `String` rather than a `ReferenceKey` so the
    /// panel can display it without formatting logic; `.currentTarget` is how
    /// it mutates that reference.
    let currentTargetDescription: String?
}

/// Result of the most recent save or load the provider attempted.
///
/// The failure case carries the typed error's description verbatim rather than
/// a friendlier paraphrase: a save that fails is a data-loss event, and the
/// exact `OpenSkySaveError` or `OpenSkySaveStoreError` text is what makes it
/// diagnosable from a screenshot.
nonisolated enum RuntimeStateSaveOutcome: Equatable {
    /// Nothing has been saved or loaded this session.
    case none
    case saved(slot: String)
    case loaded(slot: String)
    /// `operation` names what was attempted ("save" or "load") and `message`
    /// is the thrown error's description, unaltered.
    case failed(operation: String, message: String)
}

/// Live-renderer seam for the runtime world-state panel.
///
/// `refocusGameView()` is deliberately absent: `HUDControlProviding` already
/// declares it and the panel reaches it through the composed
/// `WorldControlProviders`.
@MainActor
protocol RuntimeStateControlProviding: AnyObject {
    /// One sample of everything the readout shows.
    var runtimeStateSnapshot: RuntimeStateSnapshot { get }
    /// Result of the most recent save or load, `.none` before the first one.
    var lastSaveOutcome: RuntimeStateSaveOutcome { get }
    /// Save slots currently on disk, sorted, without the file extension. Empty
    /// when the saves directory is unreachable — listing slots is a readout,
    /// not an operation, so it reports nothing rather than failing.
    var runtimeStateSaveSlots: [String] { get }

    /// Enables or disables `target`.
    ///
    /// - Returns: true when the store changed. False means the reference could
    ///   not be resolved or already held that value.
    @discardableResult
    func setReferenceEnabled(_ enabled: Bool, target: RuntimeStateTargetSelector) -> Bool

    /// Offsets `target`'s position by `RuntimeStateTuning.transformNudge`,
    /// accumulating over repeated calls.
    ///
    /// - Returns: true when the store changed.
    @discardableResult
    func nudgeReferenceTransform(target: RuntimeStateTargetSelector) -> Bool

    /// Drops every delta recorded for `target`, restoring it to plugin data.
    ///
    /// - Returns: true when the reference was dirty.
    @discardableResult
    func resetReferenceState(target: RuntimeStateTargetSelector) -> Bool

    /// Drops every delta in the store, restoring the whole world to plugin
    /// data.
    func resetAllReferenceState()

    /// Writes the current world state to `slot`, reporting the result through
    /// `lastSaveOutcome`. Never throws: a failed save is a readout state, not
    /// a caller error.
    func saveWorldState(slot: String)

    /// Replaces the current world state with `slot`'s contents, reporting the
    /// result through `lastSaveOutcome`.
    func loadWorldState(slot: String)
}
