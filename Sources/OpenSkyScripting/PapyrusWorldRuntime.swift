// Main-actor owner of the Papyrus VM in the engine loop: per-reference instance
// identity, one FIFO event queue, the fixed-step latent scheduler, and the save
// seam. Satellites: `PapyrusWorldEvents.swift`, `PapyrusWorldLifecycle.swift`,
// `PapyrusWorldPersistence.swift`. Persistent instances live until the session
// ends; a latent call on a retired instance faults when it wakes and is counted.

import DequeModule
import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsPEX
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface

@MainActor
public final class PapyrusWorldRuntime {
    /// The headless script library and instance table this runtime drives.
    public let runtime: PapyrusRuntime
    /// Fixed-step scheduler for latent calls (`Utility.Wait` and friends).
    public let scheduler: PapyrusScheduler
    /// One fixed simulation step in seconds; `advance(delta:gameClock:)`
    /// accumulates wall time into whole steps of this size.
    public let fixedStepSeconds: Double
    /// Per-tick dispatch ceiling; tests lower it to force carry-over.
    public var budget: PapyrusTickBudget = .standard
    /// Freezes the VM's own clock. While true, `advance(delta:gameClock:)` does
    /// nothing, and `stepFixed(gameClock:)` still steps one tick. Separate from
    /// `Renderer.worldSimPaused`, which pauses the whole simulation.
    public var isPaused = false

    // Stored state is internal rather than private because the lifecycle,
    // event, and persistence satellites live in separate files.
    public var instancesByKey: [PapyrusInstanceKey: PapyrusObjectHandle] = [:]
    public var keysByHandle: [PapyrusObjectHandle: PapyrusInstanceKey] = [:]
    /// Instances whose `OnInit` has been delivered. Persists in the save
    /// chunk so a restore never refires it.
    public var firedOnInit: Set<PapyrusInstanceKey> = []
    /// Instances with an `OnInit` queued but not yet delivered, so a rebuild
    /// between enqueue and dispatch cannot enqueue a second one.
    public var pendingOnInit: Set<PapyrusInstanceKey> = []
    /// Which instances each attached cell owns, so detach retires the right
    /// ones.
    public var attachedByCell: [CellSceneLocation: Set<PapyrusInstanceKey>] = [:]
    /// Instances created from an `isPersistent` reference entry; these
    /// survive `detach`.
    public var persistentKeys: Set<PapyrusInstanceKey> = []
    /// Instances belonging to a quest rather than a placed reference. Only
    /// `detachQuest(key:)` retires them. See `PapyrusWorldQuests.swift`.
    public var questInstanceKeys: Set<PapyrusInstanceKey> = []
    /// Script instances of one quest's filled aliases, keyed by the quest so
    /// `detachQuest(key:)` can retire them. The instances are keyed by the filled
    /// reference. See `PapyrusWorldQuests.swift`.
    public var questAliasInstanceKeys: [ReferenceKey: Set<PapyrusInstanceKey>] = [:]
    /// Filled quest aliases that VMAD binding resolves alias properties through. A
    /// value, so binding stays nonisolated. `.empty` without a quest layer.
    public var aliasResolution: QuestAliasResolution = .empty
    /// Newest alias filled and bound, worded like a `recentEvents` entry, for
    /// the Scripts readout. Nil until a quest with an alias starts.
    public var lastQuestAliasFill: String?
    /// Script instances belonging to a dialogue response. Nothing retires them; see
    /// `PapyrusWorldDialogue.swift`.
    public var dialogueInstanceKeys: Set<PapyrusInstanceKey> = []
    /// Dialogue result fragments enqueued this session, for the Scripts
    /// readout.
    public var dialogueFragmentsQueued = 0
    /// Scene begin, end, and phase fragments enqueued.
    public var sceneFragmentsQueued = 0
    /// Stage fragments enqueued this session, for the Scripts readout.
    public var questFragmentsQueued = 0
    /// Newest fragment enqueued, worded like a `recentEvents` entry. Nil until
    /// a stage with a fragment is set.
    public var lastQuestFragment: String?
    /// The single main-actor FIFO event queue; global order is preserved.
    public var eventQueue: [PapyrusScriptEvent] = []
    /// The next queue position a running drain reads. `retire` moves it back when it
    /// removes events the drain already passed, so the drain never reads past the end.
    var drainCursor: Int?
    /// Instances with a latent call in flight. Their queued events stay
    /// queued, in order, until the suspended handler settles.
    public var busyInstances: Set<PapyrusInstanceKey> = []
    /// Update timers for `Form.RegisterForUpdate` and friends, advanced once per
    /// fixed step by `advanceUpdateTimers(gameClock:)`.
    public var updateTimers = PapyrusUpdateTimerRegistry()
    /// Master-list resolver from the latest attach, so an event argument naming a
    /// base record (`OnHit`'s `akSource`) becomes world identity. Nil until the
    /// first attach. One resolver per session.
    public private(set) var formIDResolver: FormIDResolver?
    /// Attach, dispatch, and restore skips, for inspection and acceptance.
    public var skips = PapyrusWorldSkipTally()
    /// VMAD property-binding skips aggregated across every attach.
    public var bindingSkips = ScriptBindingTally()

    /// Resolves a script name to its compiled form on first need. Nil means no
    /// library (headless tests). Failed names go into `unresolvableScripts`, so they
    /// are not decoded again.
    public var scriptProvider: ((String) -> PexFile?)?
    /// The off-main script source used during play: a script and its ancestors, or
    /// `.loading`. Wins over `scriptProvider` when set.
    public var scriptLibrary: ((String) -> AssetLoadState<[PexFile]>)?
    /// Script names the provider already failed to resolve, keyed lowercased.
    public var unresolvableScripts: Set<String> = []
    /// Attaches and fragments that wait for a script to load, oldest first.
    public var deferredScriptWork: [PapyrusDeferredScriptWork] = []

    /// Handles for references with no script instance, such as the player. Allocated
    /// down from `UInt64.max`, while instance handles count up from 1.
    public var opaqueHandlesByKey: [ReferenceKey: PapyrusObjectHandle] = [:]
    public var opaqueKeysByHandle: [PapyrusObjectHandle: ReferenceKey] = [:]
    public var nextOpaqueHandleValue = UInt64.max
    /// Activation depth of the event currently being dispatched; 0 while
    /// nothing is dispatching, which is the depth a player use-key activation
    /// starts from. Read by `queueOnActivate(target:activator:)`.
    public private(set) var currentActivationDepth = 0

    /// What the most recent tick that actually stepped did, so an inspector
    /// can read the per-frame budget spend the callers otherwise discard.
    /// Deliberately not overwritten by a zero-step `advance`: a paused or
    /// sub-step frame would otherwise wipe the only sample there is.
    public private(set) var lastTickReport: PapyrusTickReport = .zero

    /// Preformatted names of the most recently dispatched events, oldest
    /// first, at most `recentEventLimit` of them. `eventQueue` holds what is
    /// still pending, so this is the only record of what already ran.
    public var recentEvents: [String] {
        Array(recentEventRing)
    }

    private var recentEventRing: Deque<String> = []
    /// Recent-event entries pushed out of the ring by newer ones.
    public private(set) var droppedRecentEventCount = 0

    public let suspensionTracker: PapyrusWorldSuspensionTracker
    public var accumulatorSeconds = 0.0

    /// Cap on whole steps one `advance` may run, so a long hitch cannot
    /// snowball into a burst of catch-up simulation.
    public static let maximumStepsPerAdvance = 4

    /// How deep a chain of script activations may go before `OnActivate` is refused.
    /// Player use starts at depth 0. Refusals count as
    /// `activationRecursionCappedTotal`.
    public static let maximumActivationDepth = 8

    /// Entries `recentEvents` retains, matching
    /// `RuntimeStateSnapshot.journalTailLimit`: both feed a sidebar readout
    /// that shows recent history rather than a whole session.
    public static let recentEventLimit = 8

    public static let onInitEventName = "OnInit"
    public static let onCellAttachEventName = "OnCellAttach"
    public static let onLoadEventName = "OnLoad"
    public static let onActivateEventName = "OnActivate"
    public static let onTriggerEnterEventName = "OnTriggerEnter"
    public static let onTriggerLeaveEventName = "OnTriggerLeave"
    public static let onUpdateEventName = "OnUpdate"
    public static let onUpdateGameTimeEventName = "OnUpdateGameTime"
    public static let onHitEventName = "OnHit"
    public static let onDyingEventName = "OnDying"
    public static let onDeathEventName = "OnDeath"

    /// Marks the depth every activation queued from inside this dispatch sits
    /// at. A latent handler that resumes on a later tick has lost the depth
    /// and re-enters at 0; that is a stated simplification, and the per-tick
    /// event budget still bounds the damage.
    public func withActivationDepth<Result>(
        _ depth: Int, _ body: () -> Result
    ) -> Result {
        let previous = currentActivationDepth
        currentActivationDepth = depth
        defer { currentActivationDepth = previous }
        return body()
    }

    public init(runtime: PapyrusRuntime, fixedStepSeconds: Double = 1.0 / 30.0) {
        self.runtime = runtime
        let step = fixedStepSeconds > 0 ? fixedStepSeconds : 1.0 / 30.0
        self.fixedStepSeconds = step
        scheduler = PapyrusScheduler(runtime: runtime, fixedStepSeconds: step)
        let tracker = PapyrusWorldSuspensionTracker()
        suspensionTracker = tracker
        scheduler.onResume = { call, outcome in
            tracker.noteResume(of: call, outcome: outcome)
        }
        runtime.siblingInstance = { [weak self] in self?.sibling(of: $0, as: $1) }
    }

    /// Keeps the attach's master-list resolver for later event arguments.
    /// Lives here rather than in the lifecycle satellite because the setter is
    /// private to this file.
    public func retainFormIDResolver(_ resolver: FormIDResolver) {
        formIDResolver = resolver
    }

    /// Keeps `report` as the latest tick sample. Lives here rather than in the
    /// event satellite because the setter is private to this file.
    public func retainTickReport(_ report: PapyrusTickReport) {
        lastTickReport = report
    }

    /// Appends `event` to the recent-event ring, evicting the oldest entry
    /// and counting it once the ring is full.
    public func recordDispatchedEvent(_ event: PapyrusScriptEvent) {
        recentEventRing.append(
            "\(event.functionName) -> \(event.target.scriptName)"
        )
        while recentEventRing.count > Self.recentEventLimit {
            recentEventRing.removeFirst()
            droppedRecentEventCount += 1
        }
    }

    /// Appends one event to the FIFO queue; delivery happens on a later tick.
    public func enqueue(_ event: PapyrusScriptEvent) {
        eventQueue.append(event)
    }

    /// Enqueues `OnInit` unless it already fired or is already queued.
    /// `OnInit` fires once ever per instance and the fired set persists.
    public func enqueueOnInitIfNeeded(_ key: PapyrusInstanceKey) {
        guard !firedOnInit.contains(key), !pendingOnInit.contains(key) else {
            return
        }
        pendingOnInit.insert(key)
        eventQueue.append(PapyrusScriptEvent(
            target: key, functionName: Self.onInitEventName, arguments: []
        ))
    }

    /// True once `name` is in the script library, loading it on first need. A miss
    /// is remembered. Ancestors load too, so an inherited call such as
    /// `Quest.SetStage` dispatches under the declaring script's name.
    public func resolveScript(named name: String) -> Bool {
        scriptAvailability(named: name) == .ready
    }

    /// Like `resolveScript(named:)`, but tells a script that still loads from a missing one.
    public func scriptAvailability(named name: String) -> PapyrusScriptAvailability {
        let own = scriptFileAvailability(named: name)
        guard own == .ready else { return own }
        var parent = runtime.script(named: name)?.parentClassName ?? ""
        var visited: Set<String> = [PapyrusRuntime.key(name)]
        while !parent.isEmpty, visited.insert(PapyrusRuntime.key(parent)).inserted {
            switch scriptFileAvailability(named: parent) {
            case .ready: parent = runtime.script(named: parent)?.parentClassName ?? ""
            case .loading: return .loading
            case .missing: return .ready
            }
        }
        return .ready
    }

    /// One script file into the library, with no chain walk. A miss is remembered
    /// so the next attach naming it costs a set lookup.
    private func scriptFileAvailability(named name: String) -> PapyrusScriptAvailability {
        if runtime.script(named: name) != nil {
            return .ready
        }
        let key = PapyrusRuntime.key(name)
        guard !unresolvableScripts.contains(key) else { return .missing }
        let files: [PexFile]
        if let scriptLibrary {
            switch scriptLibrary(name) {
            case .loading: return .loading
            case .failed:
                unresolvableScripts.insert(key)
                return .missing
            case let .ready(chain): files = chain
            }
        } else if let scriptProvider {
            guard let file = scriptProvider(name) else {
                unresolvableScripts.insert(key)
                return .missing
            }
            files = [file]
        } else {
            return .missing
        }
        for file in files
            where !file.objects.contains(where: { runtime.script(named: $0.name) != nil })
        {
            runtime.register(file)
        }
        // A file whose objects do not include the requested name is as useless
        // as a missing one; do not ask for it again.
        guard runtime.script(named: name) != nil else {
            unresolvableScripts.insert(key)
            return .missing
        }
        return .ready
    }

    /// One handle per world reference for VMAD object-property binding. A
    /// reference carrying several scripts resolves to the instance with the
    /// lowest script name, chosen deterministically. Alias scripts are left out.
    public func referenceHandleMap() -> [ReferenceKey: PapyrusObjectHandle] {
        var map: [ReferenceKey: PapyrusObjectHandle] = [:]
        let aliasKeys = aliasInstanceKeys
        for key in instancesByKey.keys.sorted()
            where map[key.reference] == nil && !aliasKeys.contains(key)
        {
            map[key.reference] = instancesByKey[key]
        }
        return map
    }
}

/// Nonisolated bookkeeping shared between `PapyrusScheduler.onResume` (a
/// nonisolated closure) and the main-actor world runtime. Both touch it only
/// from the main actor; the class exists because a main-actor closure cannot
/// be stored on the nonisolated scheduler.
nonisolated public final class PapyrusWorldSuspensionTracker {
    public struct StepSummary: Sendable {
        public let resumed: Int
        public let faulted: Int
        public let settledInstances: [PapyrusInstanceKey]
    }

    private var instanceByID: [UInt64: PapyrusInstanceKey] = [:]
    private var resumed = 0
    private var faulted = 0
    private var settled: [PapyrusInstanceKey] = []

    /// Marks `instance` busy under suspension `id`.
    public func begin(id: UInt64, instance: PapyrusInstanceKey) {
        instanceByID[id] = instance
    }

    /// Drops every suspension owned by a retired instance.
    public func forget(instance key: PapyrusInstanceKey) {
        instanceByID = instanceByID.filter { $0.value != key }
    }

    /// Follows one woken call: a re-suspension moves the busy marker to the
    /// new suspension id, a terminal outcome settles the instance.
    public func noteResume(of call: SuspendedCall, outcome: PapyrusRunOutcome) {
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
    public func drainStep() -> StepSummary {
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
