// Production conformer of `PapyrusWorldBridge` (issue #172): the object that
// owns the main-actor references a native is not allowed to hold itself.
//
// Ownership, so nothing here leaks: the store outlives the session and is held
// strongly; the world runtime is held weakly because it owns the native
// registry that owns this bridge; the reference source (`CellStreamer`) is
// held weakly because the same controller owns both.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyQuestsInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

@MainActor
public final class PapyrusWorldStateBridge: PapyrusWorldBridge {
    public let worldState: WorldStateStore
    /// Set immediately after the world runtime is built — it cannot be an init
    /// parameter, because the runtime is constructed with the native registry
    /// this bridge already lives inside.
    public weak var world: PapyrusWorldRuntime?
    public weak var references: (any PapyrusWorldReferenceSource)?
    /// Plugin GLOB defaults. Nil in a synthetic session, where only overrides
    /// already recorded in the store are visible.
    public var globals: GlobalStore?
    /// Quest mutation API the `Quest` natives run through (issue #322). Nil in
    /// a session with no QUST index, where every quest native fails with
    /// `PapyrusQuestBridgeError.noQuestData` rather than inventing state.
    /// Conformance lives in `PapyrusWorldStateBridgeQuests.swift`.
    public var questRuntime: (any QuestAccess)?
    /// Quests whose alias fill failed while their scripts were being attached
    /// at session wire-up (issue #183). Counted rather than thrown, because a
    /// quest that reads as running straight off its DNAM flag was never
    /// `Start`ed and so has no call to refuse; see `attachRunningQuestScripts`.
    public var questAliasFillFailures = 0
    /// Game clock the five time globals project from, matching how every other
    /// consumer builds a `GlobalResolution`.
    public var clockSource: (() -> GameClock?)?
    /// The collaborators the `Actor` natives run through (issues #375 and
    /// #424),
    /// held as closures rather than as references so the session may wire them
    /// in any order and a test may supply one without the others. Nil, or a
    /// closure answering nil, makes every actor native a tallied failure rather
    /// than a convincing zero. Conformance lives in
    /// `PapyrusWorldStateBridgeActors.swift`.
    public var actorValueRuntime: (() -> (any ActorValueAccess)?)?
    public var ragdollRuntime: (() -> (any DeathReporting)?)?
    /// The combat loop, which `StartCombat`, `StopCombat` and `IsInCombat` reach
    /// through (issue #424). Nil leaves all three tallied failures rather than
    /// letting a script claim it started a fight nothing simulates.
    public var combatRuntime: (() -> (any CombatControlling)?)?
    /// Where one actor's weapon is, or nil when this session observes no draw
    /// state for it — which is every actor but the player today.
    public var weaponDrawState: ((ReferenceKey) -> WeaponDrawState?)?
    /// The spellbook and cast loop the spell natives run through (issue #474),
    /// held as a closure for the reason the actor collaborators are: it is
    /// built by a later wiring step than this bridge. Nil, or a closure
    /// answering nil, leaves every spell native a tallied failure rather than a
    /// script that believes it taught somebody a spell.
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
    /// One perk grant or removal over the session's `PerkRuntime`, which is a
    /// struct the controller owns by value (issue #497): the closure does the
    /// read, the write and the ability reconcile, and answers whether the set
    /// changed. Held as a closure for the reason `dispelEffects` is. Nil in a
    /// session with no perk data.
    public var mutatePerks: ((PapyrusPerkMutation, ReferenceKey, ReferenceKey) -> Bool)?
    /// The perks one actor owns, or nil when this session runs no perk runtime.
    public var perkOwnership: ((ReferenceKey) -> Set<ReferenceKey>?)?
    /// One scripted skill advance over the session's `SkillAdvancementRuntime`,
    /// which is a struct the controller owns by value (issue #498): the closure
    /// does the read, the write and the write-back, and answers whether the
    /// skill took it. Held as a closure for the reason `mutatePerks` is. Nil in
    /// a session with no progression data.
    public var advanceSkill: ((PapyrusSkillAdvance, Int32, Float) -> Bool)?
    /// One read or write of the player's perk-point pool over the session's
    /// `PlayerLevelRuntime`, which is a struct the controller owns by value
    /// (issue #499): the closure applies the delta and answers the pool
    /// afterwards, so a zero delta is the read. Held as a closure for the
    /// reason `advanceSkill` is. Nil in a session with no character leveling,
    /// and both perk-point natives then refuse rather than answering zero.
    public var modifyPerkPoints: ((Int) -> Int?)?
    /// The session's crime reporter, which every crime native goes through
    /// (issue #504). Held as a getter closure for the reason `mutatePerks` is:
    /// the controller owns it and builds it after this bridge exists. Nil in a
    /// session with no crime runtime, and every crime native then refuses
    /// rather than answering zero.
    public var crimeReporter: (() -> (any CrimeReporting)?)?
    /// The session's faction runtime, which every membership native goes through
    /// (issue #508). Held as a getter closure taking the actor it is about, for
    /// two reasons: the controller owns it and builds it after this bridge
    /// exists, and seeding an actor from its authored `SNAM` run is a *mutating*
    /// call on a struct the controller stores by value, so the accessor seeds
    /// before handing the runtime over. Nil in a session with no faction data,
    /// and every membership native then refuses rather than reporting "not a
    /// member".
    public var factionRuntime: ((ReferenceKey) -> (any FactionAccess)?)?
    /// The session's relationship runtime, which the two relationship natives go
    /// through (issue #508). No actor argument, because nothing here has to be
    /// seeded: a relationship override exists only once a script writes one.
    public var relationshipRuntime: (() -> (any RelationshipAccess)?)?
    /// What one actor makes of another, derived by the session rather than here
    /// (issue #508). A closure because the derivation needs profiles the
    /// controller assembles from the streamer, the records and the store.
    public var socialDecision: ((ReferenceKey, ReferenceKey) -> PapyrusSocialDecision?)?
    /// The `NPC_` identity behind one reference, as a `RELA` record spells it.
    /// Nil for the player, who has no base record in this engine.
    public var actorSocialBase: ((ReferenceKey) -> ResolvedFormID?)?
    /// The load order's flattened `XNAM` table, which `Faction.GetReaction`
    /// reads. Separate from `factionRuntime` because it is asked about two
    /// factions rather than about an actor, so there is nothing to seed.
    public var factionRelationIndex: (() -> FactionRelationIndex?)?
    /// One actor's social profile, seeded first — what `GetCrimeFaction` and
    /// `IsGuard` read (issue #505). Nil in a session with no faction data.
    public var socialProfile: ((ReferenceKey) -> ActorSocialProfile?)?
    /// The session's arrest outcomes, which `CanPayCrimeGold`,
    /// `PlayerPayCrimeGold` and `SendPlayerToJail` go through (issue #505).
    /// A session rather than the engine's `CrimeArrest` alone because serving a
    /// sentence moves the clock and the player, which only the session owns.
    public var arrestSession: (() -> (any CrimeArrestSession)?)?
    /// Opens the barter menu against one merchant actor, for
    /// `Actor.ShowBarterMenu` (issue #506), answering the readout line and
    /// whether the menu opened. Nil in a session with no vendor data.
    public var showBarterMenu: ((ReferenceKey) -> (opened: Bool, text: String)?)?
    /// Load-order MGEF lookup, for `HasMagicEffectWithKeyword`. Nil in a
    /// synthetic session with no record index.
    public var magicEffectStore: MagicEffectStore?
    /// Master-list resolver for the FormIDs written inside decoded records —
    /// XLKR links and their keywords. Nil in a synthetic session, which falls
    /// back to the reference index.
    public var formIDResolver: FormIDResolver?

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

    public func referenceState(for key: ReferenceKey) -> ReferenceState? {
        guard let entry = references?.referenceEntry(key: key) else { return nil }
        return worldState.resolvedState(for: entry)
    }

    /// Resolves through the session's master-list resolver first — the same one
    /// every streamed reference key came from, so the two always agree — and
    /// falls back to the reference index, which is what makes a synthetic
    /// session with no resolver work.
    ///
    /// Stated limitation: one resolver covers the session, so a FormID spelled
    /// by a plugin other than the one it was built for resolves against the
    /// wrong master list. That is the same single-resolver assumption the cell
    /// builder already makes, not a new one.
    public func referenceKey(forFormID formID: FormID) -> ReferenceKey? {
        if let formIDResolver, let key = ReferenceKey.resolve(formID, using: formIDResolver) {
            return key
        }
        return references?.referenceEntry(formID: formID)?.key
    }

    public func placedReference(for key: ReferenceKey) -> PlacedReference? {
        references?.referenceEntry(key: key)?.placedReference
    }

    public func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        references?.cellLocation(of: key)
    }

    // MARK: - Writing

    /// Stores a component the VM holds. Each kind keeps the cell attribution
    /// it has always had:
    ///
    /// - A spawn is attributed to its own cell, because `cellLocation(of:)`
    ///   cannot answer for an object that is not in the world yet.
    /// - A quest, its alias table and a dialogue response belong to no cell,
    ///   so their writes are unattributed.
    /// - Everything placed (enable state, transform, activation, deletion,
    ///   inventory, actor values, death, combat, active effects) is attributed
    ///   to the reference's cell.
    ///
    /// Most of these never arrive from a native today. The gameplay natives go
    /// through their runtimes so the rules apply: `InventoryRuntime`,
    /// `QuestRuntime`, `ActorValueRuntime`, `RagdollRuntime`,
    /// `CombatLoopRuntime`, `DialogueRuntime` and `ActiveEffectRuntime`. The
    /// seam accepts them anyway: a component the VM can hold is a component the
    /// VM can store. The remaining kinds (spellbook, enchanted items, perks,
    /// factions, relationships, player progress, crime ledger) are refused.
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
             .actorValues, .death, .combat, .activeEffects:
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

    /// Records one activation and queues `OnActivate` on the target's scripts.
    ///
    /// The recursion cap is consulted first: a refused activation writes no
    /// state either, so a script pair activating each other cannot keep
    /// incrementing `activationCount` forever.
    @discardableResult
    public func activate(
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

    /// `CellStreamer.onInteraction` subscriber (issue #172): the player's
    /// use key becomes one recorded activation plus one `OnActivate` per
    /// script attached to the target.
    ///
    /// `InteractionEvent` carries a load-order-relative `FormID`, so the key
    /// comes from the streamer's decoded entry; an event for a reference no
    /// resident cell knows is dropped rather than recorded under a guessed
    /// identity. A door-style `open` action is what sets `togglesOpen`, which
    /// is how `ReferenceActivationState.isOpen` tracks doors and containers.
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
