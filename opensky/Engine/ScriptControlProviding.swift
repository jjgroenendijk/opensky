// Papyrus VM seam consumed by the World > Scripts sidebar (issue #278). No
// AppKit here on purpose: the file compiles into both the app and the CLI
// target, so a protocol added here needs no project-membership change.
//
// The seam mirrors `RuntimeStateControlProviding`: a panel reads one
// `ScriptsSnapshot` per refresh and calls one mutation entry point per user
// action. It never sees `PapyrusWorldRuntime`, `PapyrusScheduler` or
// `PapyrusTally` directly, so the engine keeps ownership of main-actor state.
// `PapyrusWorldRuntime.scriptsSnapshot(target:targetDescription:)` builds the
// snapshot; `PapyrusWorldScriptsSnapshot.swift` holds that builder.
//
// Documented in docs/engine/papyrus-vm.md.

/// One native function name and how often the session called it.
nonisolated struct ScriptsNativeCount: Equatable, Sendable {
    /// Qualified native name, as `PapyrusNativeCall.qualifiedName` spells it.
    let name: String
    let count: Int
}

/// One reference alias of a quest, as the Quests section shows it (issue
/// #183): what the record authored, and what the session filled it with.
nonisolated struct ScriptQuestAliasRow: Equatable, Sendable {
    /// ALST/ALLS number scripts and conditions address the alias by.
    let aliasID: UInt32
    /// ALID, the authoring name. Empty when the record carried none.
    let name: String
    /// `Quest.Alias.FillType.name`, so the readout states *how* an alias is
    /// meant to fill and not only whether it did.
    let fillType: String
    /// Optional aliases may legitimately stay empty; a non-optional one that
    /// does stops its quest from starting.
    let isOptional: Bool
    /// `ReferenceKey.description` of the filled reference, or nil when the
    /// alias holds nothing.
    let reference: String?
}

/// One quest's alias table for the Quests section.
nonisolated struct ScriptQuestAliasInspection: Equatable, Sendable {
    let editorID: String
    let formIDText: String
    /// Aliases are filled only while a quest runs, so a stopped quest showing
    /// every row empty is correct rather than broken.
    let isRunning: Bool
    /// Every alias the record declares, in the file order they fill in.
    let rows: [ScriptQuestAliasRow]

    var filledCount: Int {
        rows.count { $0.reference != nil }
    }
}

/// Everything the Scripts readout shows, captured in one value.
///
/// A struct rather than a set of individual protocol properties, for the same
/// reason `RuntimeStateSnapshot` is one: the panel refreshes all of these
/// together, so the readout stays a pure function of a single engine sample.
nonisolated struct ScriptsSnapshot: Equatable {
    /// Unimplemented natives a snapshot names, most-called first. The panel
    /// shows the worst offenders, not the whole tally, which runs to hundreds
    /// of names on a real install.
    static let topUnimplementedNativeLimit = 5

    static let empty = ScriptsSnapshot(
        instanceCount: 0,
        targetDescription: nil,
        targetScripts: [],
        questInstanceCount: 0,
        questCount: 0,
        runningQuestCount: 0,
        questFragmentsQueued: 0,
        lastQuestFragment: nil,
        questAliasInstanceCount: 0,
        filledAliasCount: 0,
        aliasQuestCount: 0,
        questAliasFillFailures: 0,
        lastQuestAliasFill: nil,
        recentEvents: [],
        droppedRecentEventCount: 0,
        pendingEventCount: 0,
        isPaused: false,
        pendingWaitCount: 0,
        pendingTimerCount: 0,
        tickCount: 0,
        budgetEvents: 0,
        budgetInstructions: 0,
        lastTickSteps: 0,
        lastTickDispatched: 0,
        lastTickQueued: 0,
        lastTickResumed: 0,
        lastTickFaulted: 0,
        nativeCallTotal: 0,
        implementedNativeNameCount: 0,
        unimplementedNativeTotal: 0,
        topUnimplementedNatives: []
    )

    // MARK: Instances

    /// Live script instances the world runtime owns across every attached
    /// cell, plus whatever persistent instances outlived their cell.
    let instanceCount: Int
    /// `ReferenceKey.description` of the current interaction target, or nil
    /// when nothing is targeted. A `String` rather than a `ReferenceKey` so
    /// the panel needs no formatting logic, matching
    /// `RuntimeStateSnapshot.currentTargetDescription`.
    let targetDescription: String?
    /// Script names attached to that target, sorted. Empty both when nothing
    /// is targeted and when the target carries no scripts; the panel tells
    /// those apart by `targetDescription` being nil.
    let targetScripts: [String]

    // MARK: Quests

    /// Script instances belonging to a quest rather than to a placed
    /// reference (issue #322). A subset of `instanceCount`.
    let questInstanceCount: Int
    /// Quests holding at least one of those instances.
    let questCount: Int
    /// Quests the session's state reports as running, scripted or not. Zero
    /// when the session has no quest index at all, which is also what a
    /// synthetic scene shows.
    let runningQuestCount: Int
    /// Stage fragments enqueued this session.
    let questFragmentsQueued: Int
    /// Newest stage fragment enqueued, worded like a recent-event entry. Nil
    /// until a stage carrying a fragment is set.
    let lastQuestFragment: String?
    /// Script instances belonging to a filled quest alias (issue #183). Keyed
    /// by the filled reference rather than by the quest, so these are *not* a
    /// subset of `questInstanceCount`, though they are one of `instanceCount`.
    let questAliasInstanceCount: Int
    /// Aliases filled across every quest this session.
    let filledAliasCount: Int
    /// Quests holding at least one filled alias. Lower than `runningQuestCount`
    /// whenever a running quest declares no alias, or declares only ones whose
    /// fill type OpenSky does not implement.
    let aliasQuestCount: Int
    /// Quests whose alias fill failed while their scripts were attached at
    /// wire-up. Nonzero means a start-game-enabled quest is running with an
    /// empty table it should have refused to start with.
    let questAliasFillFailures: Int
    /// Newest alias filled, worded like a recent-event entry. Nil until a quest
    /// with a fillable alias starts.
    let lastQuestAliasFill: String?

    // MARK: Events

    /// Preformatted names of the most recently dispatched events, oldest
    /// last, at most `PapyrusWorldRuntime.recentEventLimit` of them.
    let recentEvents: [String]
    /// Recent-event entries pushed out of the ring by newer ones.
    let droppedRecentEventCount: Int
    /// Events queued but not yet dispatched, carried to the next tick.
    let pendingEventCount: Int

    // MARK: Scheduler

    /// Mirror of `PapyrusWorldRuntime.isPaused`, the VM's own pause. Not the
    /// engine's menu-mode pause, which is a separate control.
    let isPaused: Bool
    /// Latent calls parked in the scheduler, `Utility.Wait` above all.
    let pendingWaitCount: Int
    /// Armed `RegisterForUpdate` timer slots across every instance.
    let pendingTimerCount: Int
    /// Fixed steps the scheduler has run this session.
    let tickCount: Int
    /// Per-tick dispatch ceiling in events.
    let budgetEvents: Int
    /// Per-tick dispatch ceiling in interpreted instructions.
    let budgetInstructions: Int

    // Fields of `PapyrusWorldRuntime.lastTickReport`, flattened so the panel
    // reads scalars rather than reaching into an engine value type.

    let lastTickSteps: Int
    let lastTickDispatched: Int
    let lastTickQueued: Int
    let lastTickResumed: Int
    let lastTickFaulted: Int

    // MARK: Native coverage

    /// Native calls the session made, implemented or not.
    let nativeCallTotal: Int
    /// Distinct native names the session called that never reported
    /// `PapyrusNativeFailure.unimplemented`. This is coverage as observed,
    /// not as registered: a native nothing has called yet is not counted.
    let implementedNativeNameCount: Int
    /// Calls that returned `PapyrusNativeFailure.unimplemented`.
    let unimplementedNativeTotal: Int
    /// The most-called unimplemented natives, at most
    /// `topUnimplementedNativeLimit` of them.
    let topUnimplementedNatives: [ScriptsNativeCount]
}

/// Live-renderer seam for the World > Scripts panel.
///
/// `refocusGameView()` is deliberately absent: `HUDControlProviding` already
/// declares it and the panel reaches it through the composed
/// `WorldControlProviders`.
@MainActor
protocol ScriptControlProviding: AnyObject {
    /// One sample of everything the readout shows. `ScriptsSnapshot.empty`
    /// when the session has no VM, which is what a synthetic scene or an
    /// install carrying no compiled scripts leaves behind.
    var scriptsSnapshot: ScriptsSnapshot { get }

    /// Freezes or resumes the VM's own tick. A paused VM accumulates no time,
    /// so resuming never replays the pause as catch-up steps. No-op when the
    /// session has no VM.
    func setScriptsPaused(_ paused: Bool)

    /// Runs `ticks` fixed steps immediately, whether or not the VM is paused.
    /// Values below one do nothing; the implementation caps the count so a
    /// stray value cannot hang the frame.
    func stepScripts(ticks: Int)

    /// Editor IDs of every quest that declares at least one alias, sorted.
    /// Empty when the session has no quest index. Quests without aliases are
    /// left out because the inspector would have nothing to say about them.
    var questAliasQuestEditorIDs: [String] { get }

    /// One quest's alias table, or nil when no loaded plugin defines a quest
    /// with that editor ID.
    func questAliasTable(editorID: String) -> ScriptQuestAliasInspection?
}
