// Main-actor owner of the Papyrus VM inside the engine loop (issue #171).
//
// `PapyrusRuntime` stays the nonisolated headless script library and instance
// table from M11.1; this type owns one for the world session and adds what
// the engine loop needs: per-reference instance identity, the single FIFO
// script-event queue, the fixed-step latent scheduler, and the save-state
// seam. Satellites: `PapyrusWorldEvents.swift` (tick and dispatch),
// `PapyrusWorldLifecycle.swift` (cell attach and detach),
// `PapyrusWorldPersistence.swift` (instance-state snapshot and restore).
//
// Stated simplifications:
// - Persistent instances are never retired, so they survive every `detach`,
//   including world-space transitions, until the session ends.
// - A latent call whose instance was retired stays in the scheduler; when it
//   wakes, the resume faults on the missing instance and is counted, which
//   keeps retirement O(instances) instead of scanning scheduler entries.

import Foundation

@MainActor
final class PapyrusWorldRuntime {
    /// The headless script library and instance table this runtime drives.
    let runtime: PapyrusRuntime
    /// Fixed-step scheduler for latent calls (`Utility.Wait` and friends).
    let scheduler: PapyrusScheduler
    /// One fixed simulation step in seconds; `advance(delta:gameClock:)`
    /// accumulates wall time into whole steps of this size.
    let fixedStepSeconds: Double
    /// Per-tick dispatch ceiling; tests lower it to force carry-over.
    var budget: PapyrusTickBudget = .standard
    /// Freezes the VM's own clock (issue #278). While true,
    /// `advance(delta:gameClock:)` returns a zero report and accumulates
    /// nothing, so unpausing never bursts through the time that passed.
    /// `stepFixed(gameClock:)` stays callable, which is what the sidebar's
    /// step-one-tick control drives.
    ///
    /// Independent of `Renderer.worldSimPaused`, which the menu-mode
    /// controller owns: menu mode delivers delta 0 to the whole world
    /// simulation, while this pauses only the script VM.
    var isPaused = false

    // Stored state is internal rather than private because the lifecycle,
    // event, and persistence satellites live in separate files.
    var instancesByKey: [PapyrusInstanceKey: PapyrusObjectHandle] = [:]
    var keysByHandle: [PapyrusObjectHandle: PapyrusInstanceKey] = [:]
    /// Instances whose `OnInit` has been delivered. Persists in the save
    /// chunk so a restore never refires it.
    var firedOnInit: Set<PapyrusInstanceKey> = []
    /// Instances with an `OnInit` queued but not yet delivered, so a rebuild
    /// between enqueue and dispatch cannot enqueue a second one.
    var pendingOnInit: Set<PapyrusInstanceKey> = []
    /// Which instances each attached cell owns, so detach retires the right
    /// ones.
    var attachedByCell: [CellSceneLocation: Set<PapyrusInstanceKey>] = [:]
    /// Instances created from an `isPersistent` reference entry; these
    /// survive `detach`.
    var persistentKeys: Set<PapyrusInstanceKey> = []
    /// The single main-actor FIFO event queue; global order is preserved.
    var eventQueue: [PapyrusScriptEvent] = []
    /// Instances with a latent call in flight. Their queued events stay
    /// queued, in order, until the suspended handler settles.
    var busyInstances: Set<PapyrusInstanceKey> = []
    /// Update timers for `Form.RegisterForUpdate` and friends (issue #277);
    /// advanced once per fixed step by `advanceUpdateTimers(gameClock:)`.
    var updateTimers = PapyrusUpdateTimerRegistry()
    /// Attach, dispatch, and restore skips, for inspection and acceptance.
    var skips = PapyrusWorldSkipTally()
    /// VMAD property-binding skips aggregated across every attach.
    var bindingSkips = ScriptBindingTally()

    /// Resolves a script name to its compiled form the first time an attach
    /// needs it. Nil means no library is available (headless tests), so only
    /// scripts registered up front exist. A name that fails to load is
    /// remembered in `unresolvableScripts` so a broken or absent script is not
    /// re-decoded on every cell attach.
    ///
    /// Decoding every `.pex` in an install up front costs far more than a
    /// session ever uses, so the library fills in lazily, one script per
    /// first use.
    var scriptProvider: ((String) -> PexFile?)?
    /// Script names the provider already failed to resolve, keyed lowercased.
    var unresolvableScripts: Set<String> = []

    /// Handles handed out for references that carry no script instance — the
    /// player above all — so a native can name them (issue #172). Allocated
    /// downwards from `UInt64.max` while `PapyrusRuntime` allocates instance
    /// handles upwards from 1, which is what keeps the two ranges apart.
    var opaqueHandlesByKey: [ReferenceKey: PapyrusObjectHandle] = [:]
    var opaqueKeysByHandle: [PapyrusObjectHandle: ReferenceKey] = [:]
    var nextOpaqueHandleValue = UInt64.max
    /// Activation depth of the event currently being dispatched; 0 while
    /// nothing is dispatching, which is the depth a player use-key activation
    /// starts from. Read by `queueOnActivate(target:activator:)`.
    private(set) var currentActivationDepth = 0

    /// What the most recent tick that actually stepped did, so an inspector
    /// can read the per-frame budget spend the callers otherwise discard.
    /// Deliberately not overwritten by a zero-step `advance`: a paused or
    /// sub-step frame would otherwise wipe the only sample there is.
    private(set) var lastTickReport: PapyrusTickReport = .zero

    /// Preformatted names of the most recently dispatched events, oldest
    /// first, at most `recentEventLimit` of them. `eventQueue` holds what is
    /// still pending, so this is the only record of what already ran.
    private(set) var recentEvents: [String] = []
    /// Recent-event entries pushed out of the ring by newer ones.
    private(set) var droppedRecentEventCount = 0

    let suspensionTracker: PapyrusWorldSuspensionTracker
    var accumulatorSeconds = 0.0

    /// Cap on whole steps one `advance` may run, so a long hitch cannot
    /// snowball into a burst of catch-up simulation.
    static let maximumStepsPerAdvance = 4

    /// How deep a chain of script-driven activations may go before the world
    /// runtime refuses to queue another `OnActivate` (issue #172). Player use
    /// keys enter at depth 0, so eight `Activate` calls may chain off one
    /// press. Refusals are tallied as `activationRecursionCappedTotal`.
    static let maximumActivationDepth = 8

    /// Entries `recentEvents` retains, matching
    /// `RuntimeStateSnapshot.journalTailLimit`: both feed a sidebar readout
    /// that shows recent history rather than a whole session.
    static let recentEventLimit = 8

    static let onInitEventName = "OnInit"
    static let onCellAttachEventName = "OnCellAttach"
    static let onLoadEventName = "OnLoad"
    static let onActivateEventName = "OnActivate"
    static let onTriggerEnterEventName = "OnTriggerEnter"
    static let onTriggerLeaveEventName = "OnTriggerLeave"
    static let onUpdateEventName = "OnUpdate"
    static let onUpdateGameTimeEventName = "OnUpdateGameTime"

    /// Marks the depth every activation queued from inside this dispatch sits
    /// at. A latent handler that resumes on a later tick has lost the depth
    /// and re-enters at 0; that is a stated simplification, and the per-tick
    /// event budget still bounds the damage.
    func withActivationDepth<Result>(
        _ depth: Int, _ body: () -> Result
    ) -> Result {
        let previous = currentActivationDepth
        currentActivationDepth = depth
        defer { currentActivationDepth = previous }
        return body()
    }

    init(runtime: PapyrusRuntime, fixedStepSeconds: Double = 1.0 / 30.0) {
        self.runtime = runtime
        let step = fixedStepSeconds > 0 ? fixedStepSeconds : 1.0 / 30.0
        self.fixedStepSeconds = step
        scheduler = PapyrusScheduler(runtime: runtime, fixedStepSeconds: step)
        let tracker = PapyrusWorldSuspensionTracker()
        suspensionTracker = tracker
        scheduler.onResume = { call, outcome in
            tracker.noteResume(of: call, outcome: outcome)
        }
    }

    /// Keeps `report` as the latest tick sample. Lives here rather than in the
    /// event satellite because the setter is private to this file.
    func retainTickReport(_ report: PapyrusTickReport) {
        lastTickReport = report
    }

    /// Appends `event` to the recent-event ring, evicting the oldest entry
    /// and counting it once the ring is full.
    func recordDispatchedEvent(_ event: PapyrusScriptEvent) {
        recentEvents.append(
            "\(event.functionName) -> \(event.target.scriptName)"
        )
        while recentEvents.count > Self.recentEventLimit {
            recentEvents.removeFirst()
            droppedRecentEventCount += 1
        }
    }

    /// Appends one event to the FIFO queue; delivery happens on a later tick.
    func enqueue(_ event: PapyrusScriptEvent) {
        eventQueue.append(event)
    }

    /// Enqueues `OnInit` unless it already fired or is already queued.
    /// `OnInit` fires once ever per instance and the fired set persists.
    func enqueueOnInitIfNeeded(_ key: PapyrusInstanceKey) {
        guard !firedOnInit.contains(key), !pendingOnInit.contains(key) else {
            return
        }
        pendingOnInit.insert(key)
        eventQueue.append(PapyrusScriptEvent(
            target: key, functionName: Self.onInitEventName, arguments: []
        ))
    }

    /// True once `name` is in the script library, loading it through
    /// `scriptProvider` on first need. A provider miss is remembered, so the
    /// second attach naming a missing script costs a set lookup.
    func resolveScript(named name: String) -> Bool {
        if runtime.script(named: name) != nil {
            return true
        }
        let key = PapyrusRuntime.key(name)
        guard let scriptProvider, !unresolvableScripts.contains(key) else {
            return false
        }
        guard let file = scriptProvider(name) else {
            unresolvableScripts.insert(key)
            return false
        }
        runtime.register(file)
        // A file whose objects do not include the requested name is as useless
        // as a missing one; do not ask for it again.
        guard runtime.script(named: name) != nil else {
            unresolvableScripts.insert(key)
            return false
        }
        return true
    }

    /// One handle per world reference for VMAD object-property binding. A
    /// reference carrying several scripts resolves to the instance with the
    /// lowest script name, chosen deterministically.
    func referenceHandleMap() -> [ReferenceKey: PapyrusObjectHandle] {
        var map: [ReferenceKey: PapyrusObjectHandle] = [:]
        for key in instancesByKey.keys.sorted() where map[key.reference] == nil {
            map[key.reference] = instancesByKey[key]
        }
        return map
    }
}

/// Nonisolated bookkeeping shared between `PapyrusScheduler.onResume` (a
/// nonisolated closure) and the main-actor world runtime. Both touch it only
/// from the main actor; the class exists because a main-actor closure cannot
/// be stored on the nonisolated scheduler.
nonisolated final class PapyrusWorldSuspensionTracker {
    struct StepSummary {
        let resumed: Int
        let faulted: Int
        let settledInstances: [PapyrusInstanceKey]
    }

    private var instanceByID: [UInt64: PapyrusInstanceKey] = [:]
    private var resumed = 0
    private var faulted = 0
    private var settled: [PapyrusInstanceKey] = []

    /// Marks `instance` busy under suspension `id`.
    func begin(id: UInt64, instance: PapyrusInstanceKey) {
        instanceByID[id] = instance
    }

    /// Drops every suspension owned by a retired instance.
    func forget(instance key: PapyrusInstanceKey) {
        instanceByID = instanceByID.filter { $0.value != key }
    }

    /// Follows one woken call: a re-suspension moves the busy marker to the
    /// new suspension id, a terminal outcome settles the instance.
    func noteResume(of call: SuspendedCall, outcome: PapyrusRunOutcome) {
        resumed += 1
        let key = instanceByID.removeValue(forKey: call.id)
        switch outcome {
        case let .suspended(next):
            if let key {
                instanceByID[next.id] = key
            }
        case .completed:
            if let key {
                settled.append(key)
            }
        case .faulted:
            faulted += 1
            if let key {
                settled.append(key)
            }
        }
    }

    /// Returns and resets the per-step counters.
    func drainStep() -> StepSummary {
        defer {
            resumed = 0
            faulted = 0
            settled.removeAll()
        }
        return StepSummary(
            resumed: resumed, faulted: faulted, settledInstances: settled
        )
    }
}
