// The production `PapyrusWorldBridge`: owns the main-actor references natives may not
// hold. The store is strong; the world runtime and `CellStreamer` are weak, because
// they own this bridge or share its owner.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

@MainActor
public final class PapyrusWorldStateBridge: PapyrusWorldBridge {
    public let worldState: WorldStateStore
    /// Set immediately after the world runtime is built — it cannot be an init
    /// parameter, because the runtime is constructed with the native registry
    /// this bridge already lives inside.
    public weak var world: PapyrusWorldRuntime? {
        didSet {
            world?.attachOnUse = { [weak self] in self?.attachOnUse($0) ?? false }
            world?.scriptsOfTarget = { [weak self] in self?.scriptsOfTarget($0) ?? [] }
        }
    }

    public weak var references: (any PapyrusWorldReferenceSource)?
    /// Plugin GLOB defaults. Nil in a synthetic session, where only overrides
    /// already recorded in the store are visible.
    public var globals: GlobalStore?
    /// Quest mutation API for the `Quest` natives. Nil without QUST data, where they fail
    /// with `PapyrusQuestBridgeError.noQuestData`. See `PapyrusWorldStateBridgeQuests.swift`.
    public var questRuntime: (any QuestAccess)?
    /// Quests whose alias fill failed while scripts were attached at wire-up. Counted,
    /// not thrown: a quest running from its DNAM flag has no `Start` call to refuse.
    public var questAliasFillFailures = 0
    /// Who stands in each trigger volume, kept from the enter and leave events.
    public internal(set) var triggerOccupants: [ReferenceKey: Set<ReferenceKey>] = [:]
    /// Seconds since the last `OnTrigger` repeat.
    var triggerRepeatElapsed: Float = 0
    /// Activate children still waiting out their `XAPR` delay, in the order they were queued.
    public internal(set) var delayedActivations: [DelayedActivation] = []
    /// The actor `KillSilent` is killing, so the host skips the story-manager `KILL` event.
    public internal(set) var silentDeath: ReferenceKey?
    public var factionNatives = PapyrusFactionNatives()
    public var actorNatives = PapyrusActorNatives()
    public var magicNatives = PapyrusMagicNatives()
    public var progressionNatives = PapyrusProgressionNatives()
    public var crimeNatives = PapyrusCrimeNatives()
    public var playerNatives = PapyrusPlayerNatives()
    public var perceptionNatives = PapyrusPerceptionNatives()
    public var sessionNatives = PapyrusSessionNatives()
    /// Load-order MGEF lookup, for `HasMagicEffectWithKeyword`. Nil in a
    /// synthetic session with no record index.
    public var magicEffectStore: MagicEffectStore?
    /// Load-order FLST lookup, for the `FormList` natives. Nil fails them.
    public var formListStore: FormListStore?
    /// Load-order KYWD and `KWDA` lookup, for `HasKeyword`. Nil fails it.
    public var keywordStore: KeywordStore?
    /// Master-list resolver for the FormIDs written inside decoded records —
    /// XLKR links and their keywords. Nil in a synthetic session, which falls
    /// back to the reference index.
    public var formIDResolver: FormIDResolver?
    /// The story manager and scenes, for the `Keyword` and `Scene` natives.
    public weak var story: (any PapyrusStoryBridge)?
    /// The race menu, map markers, fast travel, and the player's identity.
    public weak var menus: (any PapyrusMenuBridge)?
    /// Hazards and explosions that `PlaceAtMe` places.
    public weak var trapWorld: (any PapyrusTrapWorldBridge)?
    /// Object behaviour graphs, for the animation natives. Nil paces them.
    public weak var objectAnimation: (any PapyrusObjectAnimationBridge)?
    /// Notifications, message boxes, and camera effects. Nil in a headless session.
    public weak var presenter: (any PapyrusPresenting)?
    public var itemNotices = ItemNoticeTexts.vanilla
    /// Visual effects, effect shaders, and image-space modifiers. Nil in a headless session.
    public weak var effectPresenter: (any PapyrusEffectPresenting)?
    /// The sky, for the `Weather` natives. Nil in a headless session.
    public weak var weather: (any PapyrusWeatherControlling)?
    public weak var music: (any PapyrusMusicControlling)?
    /// Packages, vehicles, and idles for the actor AI natives.
    public weak var actorAI: (any PapyrusActorAIBridge)?
    /// Inventories and equipment, for the item natives.
    public weak var inventory: (any PapyrusInventoryBridge)?
    /// The first journal entry `queueInventoryEvents` has not read; nil before its first call.
    var inventoryJournalCursor: UInt64?
    /// The first journal entry `queueMagicEffectEvents` has not read; nil before its first call.
    var effectJournalCursor: UInt64?
    /// The first journal entry `queueReferenceStateEvents` has not read.
    var referenceJournalCursor: UInt64?
    var statsJournalCursor: UInt64?
    /// Each scripted actor's combat activity at the last `queueCombatStateEvents`.
    var lastCombatActivity: [ReferenceKey: ActorCombatActivity] = [:]
    /// Scripted moves in progress. See `PapyrusWorldTranslations.swift`.
    public internal(set) var translations: [ReferenceKey: PapyrusTranslation] = [:]

    /// Lazily built reverse map for the global lookups, which are keyed by
    /// `ReferenceKey` on the Papyrus side and by `FormID` on the store side.
    private var globalFormIDsByKey: [ReferenceKey: FormID]?

    public init(
        worldState: WorldStateStore,
        world: PapyrusWorldRuntime? = nil,
        references: (any PapyrusWorldReferenceSource)? = nil,
        globals: GlobalStore? = nil
    ) {
        self.worldState = worldState
        self.world = world
        self.references = references
        self.globals = globals
    }

    public var playerKey: ReferenceKey {
        .player
    }

    // MARK: - Identity

    public func referenceKey(for handle: PapyrusObjectHandle) -> ReferenceKey? {
        world?.referenceKey(for: handle)
    }

    public func objectHandle(for key: ReferenceKey) -> PapyrusObjectHandle? {
        world?.objectHandle(for: key)
    }

    // MARK: - Reading

    /// The enabled flag follows a resident `XESP` parent, as the cell build does. A
    /// scripted move shows its live pose.
    public func referenceState(for key: ReferenceKey) -> ReferenceState? {
        guard let entry = references?.referenceEntry(key: key) else { return nil }
        var state = worldState.resolvedState(for: entry)
        if let move = translations[key] {
            state.transform = move.pose(scale: state.transform.scale)
        }
        guard entry.enableParent != nil else { return state }
        let store = worldState
        let resolver = EnableParentResolver(
            delta: { store.delta(for: $0) },
            parent: { [references] in references?.referenceEntry(formID: $0) }
        )
        state.enableState = ReferenceEnableState(isEnabled: resolver.isEnabled(entry))
        return state
    }

    /// Resolves through the session's master-list resolver, then the reference index for
    /// synthetic sessions. One resolver per session, as in the cell builder, so another
    /// plugin's FormID spelling resolves wrongly.
    public func referenceKey(forFormID formID: FormID) -> ReferenceKey? {
        if let formIDResolver, let key = ReferenceKey.resolve(formID, using: formIDResolver) {
            return key
        }
        return references?.referenceEntry(formID: formID)?.key
    }

    public func placedReference(for key: ReferenceKey) -> PlacedReference? {
        references?.referenceEntry(key: key)?.placedReference
    }

    public func baseObject(of key: ReferenceKey) -> FormID? {
        guard let entry = references?.referenceEntry(key: key) else { return nil }
        return entry.placedReference?.base ?? entry.placedActor?.base
    }

    public func triggerObjectCount(for key: ReferenceKey) -> Int {
        triggerOccupants[key]?.count ?? 0
    }

    public func lockState(for key: ReferenceKey) -> ReferenceLockState? {
        ReferenceLockState.resolve(
            baseline: placedReference(for: key)?.lock,
            delta: worldState.component(ReferenceLockState.self, for: key)
        )
    }

    public func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        references?.cellLocation(of: key)
    }

    // MARK: - Writing

    /// Stores a component the VM holds. A spawn uses its own cell; quests, aliases and
    /// dialogue have none; placed state uses the reference's cell. Gameplay natives use
    /// their runtimes instead. Spellbook, enchantment, perk, faction, progress and
    /// crime kinds are refused. A transform write ends a scripted move.
    @discardableResult
    public func write(
        _ component: WorldStateComponentValue, for key: ReferenceKey
    ) -> Bool {
        switch component.kind {
        case .spawn:
            guard let spawn = component.value(as: ReferenceSpawnState.self) else { return false }
            return worldState.set(spawn, for: key, in: spawn.location)
        case .quest, .questAliases, .dialogue:
            return worldState.set(component.base, for: key)
        case .transform:
            endTranslation(of: key)
            return worldState.set(component.base, for: key, in: cellLocation(of: key))
        case .enableState, .activation, .deletion, .inventory,
             .actorValues, .death, .combat, .activeEffects, .lock:
            return worldState.set(component.base, for: key, in: cellLocation(of: key))
        default:
            return false
        }
    }

    // MARK: - Activation

    /// Records one activation, queues `OnActivate` on the target's scripts, and
    /// passes it to the target's `XAPR` activate children, each activated by its
    /// parent. A child with a delay waits for `advanceDelayedActivations`. Each
    /// reference is activated at most once per call, so a cycle ends.
    @discardableResult
    public func activate(
        _ target: ReferenceKey,
        by activator: ReferenceKey,
        togglesOpen: Bool
    ) -> PapyrusActivationOutcome {
        let outcome = activateOne(target, by: activator, togglesOpen: togglesOpen)
        guard !outcome.cappedByRecursion else { return outcome }
        var queuedEvents = outcome.queuedEvents
        var visited: Set = [target]
        var parents = [target]
        while let parent = parents.popLast() {
            for child in references?.activateChildren(of: parent) ?? []
                where visited.insert(child.key).inserted
            {
                guard child.delay <= 0 else {
                    delayedActivations.append(DelayedActivation(
                        child: child.key, parent: parent, remaining: child.delay
                    ))
                    continue
                }
                queuedEvents += activateOne(child.key, by: parent, togglesOpen: false)
                    .queuedEvents
                parents.append(child.key)
            }
        }
        return PapyrusActivationOutcome(
            recorded: outcome.recorded, queuedEvents: queuedEvents, cappedByRecursion: false
        )
    }

    /// The recursion cap is consulted first: a refused activation writes no
    /// state either, so a script pair activating each other cannot keep
    /// incrementing `activationCount` forever.
    private func activateOne(
        _ target: ReferenceKey,
        by activator: ReferenceKey,
        togglesOpen: Bool
    ) -> PapyrusActivationOutcome {
        let queued = world?.queueOnActivate(target: target, activator: activator)
            ?? .none
        guard !queued.cappedByRecursion else { return queued }
        let current = worldState.component(ReferenceActivationState.self, for: target)
            ?? referenceState(for: target)?.activation
            ?? .untouched
        let recorded = write(
            current.activated(
                by: activator,
                togglesOpen: togglesOpen && !isActivationBlocked(target)
            )
            .erased,
            for: target
        )
        return PapyrusActivationOutcome(
            recorded: recorded,
            queuedEvents: queued.queuedEvents,
            cappedByRecursion: false
        )
    }

    // MARK: - Update timers

    public func registerUpdateTimer(
        handle: PapyrusObjectHandle,
        slot: PapyrusUpdateTimerSlot,
        interval: Double
    ) {
        world?.registerUpdateTimer(handle: handle, slot: slot, interval: interval)
    }

    public func unregisterUpdateTimers(
        handle: PapyrusObjectHandle,
        family: PapyrusUpdateTimerFamily
    ) {
        world?.unregisterUpdateTimers(handle: handle, family: family)
    }

    /// `CellStreamer.onInteraction` subscriber: records one activation and queues one
    /// `OnActivate` per script. An unknown reference is dropped. A door-style `open` sets
    /// `togglesOpen`, which drives `ReferenceActivationState.isOpen`.
    @discardableResult
    public func handleInteraction(_ event: InteractionEvent) -> PapyrusActivationOutcome {
        let interaction = event.target.interaction
        guard
            let entry = references?.referenceEntry(formID: interaction.reference)
        else { return .none }
        return activate(
            entry.key,
            by: playerKey,
            togglesOpen: interaction.action == .open
        )
    }
}

extension PapyrusWorldStateBridge {
    public func globalValue(for key: ReferenceKey) -> GlobalValue? {
        guard let globals, let id = globalFormID(for: key) else {
            return worldState.globalValue(for: key)
        }
        return worldState
            .globalResolution(defaults: globals, clock: sessionNatives.clockSource?())
            .value(for: id)
    }

    /// A write with no GLOB record behind it — a synthetic session, or a key
    /// the loaded plugins do not define — keeps whatever type an existing
    /// override declared and otherwise treats the value as a float, rather
    /// than inventing a `short`/`long` rounding rule the plugin never stated.
    @discardableResult
    public func setGlobal(_ raw: Float, for key: ReferenceKey) -> Bool {
        if let globals, let id = globalFormID(for: key) {
            return worldState.setGlobal(raw, formID: id, defaults: globals)
        }
        let type = worldState.globalValue(for: key)?.type ?? .float
        return worldState.setGlobal(raw, type: type, for: key)
    }

    private func globalFormID(for key: ReferenceKey) -> FormID? {
        if let globalFormIDsByKey {
            return globalFormIDsByKey[key]
        }
        var map: [ReferenceKey: FormID] = [:]
        for global in globals?.sortedGlobals() ?? [] {
            guard let globalKey = globals?.key(for: global.formID) else { continue }
            map[globalKey] = global.formID
        }
        globalFormIDsByKey = map
        return map[key]
    }
}
