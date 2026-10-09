// The production `PapyrusWorldBridge`: owns the main-actor references natives may not
// hold. The store is strong; the world runtime and `CellStreamer` are weak, because
// they own this bridge or share its owner.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatInterface
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
    /// Game clock the five time globals project from, matching how every other
    /// consumer builds a `GlobalResolution`.
    public var clockSource: (() -> GameClock?)?
    /// Picks which log entry of a stage runs its fragment. Nil runs every entry's fragment.
    public var logEntryEvaluator: (() -> ConditionEvaluator)?
    /// The `Actor` native collaborators, as closures so they can be wired in any order.
    /// Nil makes every actor native a tallied failure, not a fake zero. See
    /// `PapyrusWorldStateBridgeActors.swift`.
    public var actorValueRuntime: (() -> (any ActorValueAccess)?)?
    public var ragdollRuntime: (() -> (any DeathReporting)?)?
    /// The combat loop behind `StartCombat`, `StopCombat` and `IsInCombat`. Nil leaves
    /// them tallied failures.
    public var combatRuntime: (() -> (any CombatControlling)?)?
    /// Where one actor's weapon is, or nil when this session observes no draw
    /// state for it — which is every actor but the player today.
    public var weaponDrawState: ((ReferenceKey) -> WeaponDrawState?)?
    /// The spellbook and cast loop for spell natives, as a closure because it is wired
    /// later. Nil leaves every spell native a tallied failure.
    public var casterRuntime: (() -> (any SpellCasting)?)?
    /// One dispel over the session's `ActiveEffectRuntime`, which is a struct
    /// the controller owns by value: the closure does the read, the removal and
    /// the write-back, and answers how many effects went. Nil in a session with
    /// no effect runtime.
    public var dispelEffects: ((ActorValueHolder, @escaping (ActiveEffect) -> Bool) -> Int)?
    /// The one seam a landed spell applies through, shared with projectiles and
    /// enchantments, so `Spell.Cast` at a named target resists exactly as a
    /// fireball does. Nil in a session with no effect runtime.
    public var applySpellHit: ((SpellHit) -> SpellHitReport)?
    /// One perk grant or removal over the controller's `PerkRuntime` value, including
    /// the ability reconcile; answers whether the set changed. Nil without perk data.
    public var mutatePerks: ((PapyrusPerkMutation, ReferenceKey, ReferenceKey) -> Bool)?
    /// The perks one actor owns, or nil when this session runs no perk runtime.
    public var perkOwnership: ((ReferenceKey) -> Set<ReferenceKey>?)?
    /// One scripted skill advance over the controller's `SkillAdvancementRuntime` value;
    /// answers whether the skill took it. Nil without progression data.
    public var advanceSkill: ((PapyrusSkillAdvance, Int32, Float) -> Bool)?
    /// Applies a delta to the player's perk points over `PlayerLevelRuntime` and returns
    /// the pool; zero reads it. Nil without leveling, and the natives then refuse.
    public var modifyPerkPoints: ((Int) -> Int?)?
    /// The session's crime reporter, as a getter because it is built later. Nil without a
    /// crime runtime, and every crime native then refuses.
    public var crimeReporter: (() -> (any CrimeReporting)?)?
    /// The faction runtime for membership natives, seeded for the given actor first
    /// (a mutating call on the controller's value). Nil without faction data, and the
    /// natives refuse instead of answering "not a member".
    public var factionRuntime: ((ReferenceKey) -> (any FactionAccess)?)?
    /// The relationship runtime for the two relationship natives. No actor argument: an
    /// override exists only once a script writes one.
    public var relationshipRuntime: (() -> (any RelationshipAccess)?)?
    /// What one actor makes of another, derived by the session from streamer, records
    /// and store.
    public var socialDecision: ((ReferenceKey, ReferenceKey) -> PapyrusSocialDecision?)?
    /// The `NPC_` identity behind one reference, as a `RELA` record spells it.
    /// Nil for the player, who has no base record in this engine.
    public var actorSocialBase: ((ReferenceKey) -> ResolvedFormID?)?
    /// The load order's flattened `XNAM` table, which `Faction.GetReaction`
    /// reads. Separate from `factionRuntime` because it is asked about two
    /// factions rather than about an actor, so there is nothing to seed.
    public var factionRelationIndex: (() -> FactionRelationIndex?)?
    /// One actor's seeded social profile, for `GetCrimeFaction` and `IsGuard`. Nil
    /// without faction data.
    public var socialProfile: ((ReferenceKey) -> ActorSocialProfile?)?
    /// Arrest outcomes for `CanPayCrimeGold`, `PlayerPayCrimeGold` and `SendPlayerToJail`.
    /// The session owns them, because a sentence moves the clock and the player.
    public var arrestSession: (() -> (any CrimeArrestSession)?)?
    /// Opens the barter menu for `Actor.ShowBarterMenu`, returning the readout line and
    /// whether it opened. Nil without vendor data.
    public var showBarterMenu: ((ReferenceKey) -> (opened: Bool, text: String)?)?
    /// Load-order MGEF lookup, for `HasMagicEffectWithKeyword`. Nil in a
    /// synthetic session with no record index.
    public var magicEffectStore: MagicEffectStore?
    /// Load-order FLST lookup, for the `FormList` natives. Nil fails them.
    public var formListStore: FormListStore?
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
    /// Notifications, message boxes, and camera effects. Nil in a headless session.
    public weak var presenter: (any PapyrusPresenting)?
    /// Packages, vehicles, and idles for the actor AI natives.
    public weak var actorAI: (any PapyrusActorAIBridge)?

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

    /// The enabled flag follows a resident `XESP` parent, as the cell build does.
    public func referenceState(for key: ReferenceKey) -> ReferenceState? {
        guard let entry = references?.referenceEntry(key: key) else { return nil }
        var state = worldState.resolvedState(for: entry)
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

    public func formListEntries(of key: ReferenceKey) -> [ReferenceKey?]? {
        guard
            let formListStore,
            case let .plugin(plugin, objectID) = key,
            let resolved = formListStore.formList(ResolvedFormID(
                plugin: plugin,
                objectID: objectID
            ))
        else { return nil }
        return resolved.list.entries.map { entry in
            entry
                .flatMap { formListStore.resolvedID($0, fromPlugin: resolved.sourcePlugin) }
                .map(ReferenceKey.init(resolved:))
        }
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
    /// crime kinds are refused.
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
        case .enableState, .transform, .activation, .deletion, .inventory,
             .actorValues, .death, .combat, .activeEffects, .lock:
            return worldState.set(component.base, for: key, in: cellLocation(of: key))
        default:
            return false
        }
    }

    // MARK: - Globals

    public func globalValue(for key: ReferenceKey) -> GlobalValue? {
        guard let globals, let id = globalFormID(for: key) else {
            return worldState.globalValue(for: key)
        }
        return worldState
            .globalResolution(defaults: globals, clock: clockSource?())
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

    // MARK: - Activation

    /// Records one activation, queues `OnActivate` on the target's scripts, and
    /// passes it to the target's `XAPR` activate children, each activated by its
    /// parent. Each reference is activated at most once per call, so a cycle ends.
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
                where visited.insert(child).inserted
            {
                queuedEvents += activateOne(child, by: parent, togglesOpen: false).queuedEvents
                parents.append(child)
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
            current.activated(by: activator, togglesOpen: togglesOpen).erased,
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
