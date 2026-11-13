// The shell of the magic domain: owns the active-effect runtime, the caster
// runtime and the enchantment index, steps them, and is the world the cast loop
// resolves through. The rules live in `MagicCore`. See docs/engine/coordinators.md.

import OpenSkyActorsInterface
public import OpenSkyConditions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import OpenSkyWorldState

/// Owns the magic runtimes and reads the world through `MagicWorld`.
@MainActor
public final class MagicCoordinator {
    /// Nil without an MGEF index. A value over a shared store, so every change
    /// goes through `withEffects`.
    public internal(set) var effects: ActiveEffectRuntime?
    /// Nil without a SPEL index. Set once in the initializer, because it reads
    /// the world through this coordinator.
    public private(set) var caster: CasterRuntime?
    private(set) lazy var casterBridge = CasterBridge(coordinator: self)
    /// The plugin every magic item's EFID links are relative to.
    public let pluginName: String
    /// The plugin an actor's `SPLO` links are relative to.
    public let spellPluginName: String?
    /// The ENCH index.
    public let enchantmentStore: EnchantmentStore?

    let world: any MagicWorld
    /// What the effects asked of the app. A frame step returns and empties it.
    var pendingCommands: [MagicCommand] = []
    /// Takes `CAST`.
    public weak let storyEvents: (any StoryEventReporting)?

    /// Owned here, not by the runtime, because the runtime is a value and a
    /// per-copy accumulator would split the simulation.
    var accumulator: Double = 0
    /// The player's accumulator while Slow Time splits the clocks.
    var playerAccumulator: Double = 0
    /// Seconds since the last cloak pulse.
    var cloakClock: Float = 0
    /// Seconds since the last ability reconcile.
    var abilityClock: Float = 0
    /// Actors a load gave timed effects whose modifiers are not rebuilt yet.
    var pendingModifierRebuild: Set<ReferenceKey> = []
    /// Seconds each broken ward stays in `IsWardState` 2.
    var brokenWardSeconds: [ReferenceKey: Float] = [:]
    /// The absorption roll, in 0 ..< 100. A test fixes it.
    var spellDefenceRoll = WardShields.seededDefenceRoll()

    /// Every SHOU in the load order, by key.
    public let shouts: [ReferenceKey: ResolvedShout]
    /// The load order's shouts, for an NPC's spell list.
    let shoutStore: ShoutStore?
    public internal(set) var shoutMachine = ShoutMachine()
    /// Dismissed summons and the seconds before each goes.
    var fadingSummons: [(actor: CommandedActor, seconds: Float)] = []
    /// Summoned and reanimated actors, oldest first. Not saved.
    public internal(set) var commanded: [CommandedActor] = []
    /// Detect Life paint, Telekinesis and Grab Actor holds, and Guide trails. Not saved.
    var holds: [MagicHold] = []
    /// Lights the Light archetype placed. Not saved.
    public internal(set) var magicLights: [MagicLight] = []
    /// Each system's game settings, as the session read them.
    let rules: MagicRules
    /// The words the readouts and notices show.
    let texts: MagicSessionTexts
    var castingState = CastingState()
    var shoutState = ShoutState()
    var runeState = RuneState()
    var enchantingMemory = EnchantingMemory()

    /// Where each caster aimed its last target-location summon.
    var summonPoints: [ReferenceKey: SIMD3<Float>] = [:]
    let spellBaselines: ActorSpellBaselineResolver?
    /// Actors whose authored spell list was granted, so it happens once.
    var grantedActors: Set<ReferenceKey> = []
    var lastEffectAction = MagicEffectActionOutcome.idle

    /// Without data there is no game: every runtime is nil, and each action says so.
    public init(
        world: any MagicWorld,
        data: MagicSessionData = MagicSessionData(),
        storyEvents: (any StoryEventReporting)? = nil
    ) {
        self.world = world
        self.storyEvents = storyEvents
        effects = data.effects.map {
            ActiveEffectRuntime(values: $0.values, effects: $0.store, conditions: $0.conditions)
        }
        pluginName = data.effects?.pluginName ?? ""
        spellPluginName = data.casting?.spellPluginName
        spellBaselines = data.casting?.baselines
        enchantmentStore = data.enchantments
        shoutStore = data.shouts
        shouts = MagicCoordinator.ShoutVoice.shoutsByKey(data.shouts)
        rules = data.rules
        texts = data.texts
        if let casting = data.casting {
            let runtime = CasterRuntime(
                spellbook: casting.spellbook, values: casting.values, world: casterBridge
            )
            runtime.costSettings = rules.spellCost
            caster = runtime
            runtime.staffs = casterBridge
        }
        archetypeLookups.prepareArchetypeLookups()
    }

    /// Runs one change on the effect runtime and stores it back. Nil without one.
    @discardableResult
    public func withEffects<Result>(
        _ body: (inout ActiveEffectRuntime) throws -> Result
    ) rethrows -> Result? {
        guard var runtime = effects else { return nil }
        // Written back on a throw too, as an `inout` argument would be.
        defer {
            effects = runtime
            archetypeActions.performWorldActions()
        }
        return try body(&runtime)
    }

    @discardableResult
    func recordEffect(_ outcome: MagicEffectActionOutcome) -> MagicEffectActionOutcome {
        lastEffectAction = outcome
        return outcome
    }

    @discardableResult
    func recordCasting(_ outcome: CastingActionOutcome) -> CastingActionOutcome {
        castingState.lastCastingAction = outcome
        return outcome
    }
}

extension MagicCoordinator {
    func associatedItem(of effect: ReferenceKey) -> ResolvedFormID? {
        guard let store = effects?.effects, let resolved = store.effect(key: effect) else {
            return nil
        }
        return store.associatedItem(of: resolved)
    }
}

extension MagicCoordinator {
    var abilityReconciler: AbilityReconciler {
        AbilityReconciler(coordinator: self)
    }

    public var archetypeActions: ArchetypeActions {
        ArchetypeActions(coordinator: self)
    }

    var archetypeLookups: ArchetypeLookups {
        ArchetypeLookups(coordinator: self)
    }

    var cloakPulses: CloakPulses {
        CloakPulses(coordinator: self)
    }

    var castingCues: CastingCueTracker {
        CastingCueTracker(coordinator: self)
    }

    var conditionReads: ConditionReads {
        ConditionReads(coordinator: self)
    }

    var enchantingTable: EnchantingTable {
        EnchantingTable(coordinator: self)
    }

    var enchantingRecords: EnchantingRecords {
        EnchantingRecords(coordinator: self)
    }

    var holdEffects: HoldEffects {
        HoldEffects(coordinator: self)
    }

    public var menuLines: MenuLines {
        MenuLines(coordinator: self)
    }

    public var enchanter: Enchanter {
        Enchanter(coordinator: self)
    }

    public var magicMenu: MagicMenu {
        MagicMenu(coordinator: self)
    }

    var controlPanels: ControlPanels {
        ControlPanels(coordinator: self)
    }

    var effectsPanel: EffectsPanel {
        EffectsPanel(coordinator: self)
    }

    var perkEffects: PerkEffects {
        PerkEffects(coordinator: self)
    }

    var raceEffects: RaceEffects {
        RaceEffects(coordinator: self)
    }

    var weaponRecharge: WeaponRecharge {
        WeaponRecharge(coordinator: self)
    }

    var runePlacement: RunePlacement {
        RunePlacement(coordinator: self)
    }

    public var shoutVoice: ShoutVoice {
        ShoutVoice(coordinator: self)
    }

    var spellTomes: SpellTomes {
        SpellTomes(coordinator: self)
    }

    var slowTimeClock: SlowTimeClock {
        SlowTimeClock(coordinator: self)
    }

    public var soulTrapping: SoulTrapping {
        SoulTrapping(coordinator: self)
    }

    var summonCommands: SummonCommands {
        SummonCommands(coordinator: self)
    }

    var wardShields: WardShields {
        WardShields(coordinator: self)
    }

    public var worldArchetypeActions: WorldArchetypeActions {
        WorldArchetypeActions(coordinator: self)
    }

    var weaponArchetypes: WeaponArchetypes {
        WeaponArchetypes(coordinator: self)
    }

    var shoutReadout: ShoutReadout {
        ShoutReadout(coordinator: self)
    }

    var enchantingReadout: EnchantingReadout {
        EnchantingReadout(coordinator: self)
    }

    /// Keeps each actor's race, perk and authored abilities applied.
    struct AbilityReconciler {
        let coordinator: MagicCoordinator
    }

    /// Runs the world actions effect archetypes ask for, and the cloak pulses.
    public struct ArchetypeActions {
        let coordinator: MagicCoordinator
    }

    /// The lookups the effect runtime asks at load: source categories and undead actors.
    struct ArchetypeLookups {
        let coordinator: MagicCoordinator
    }

    /// Cloaks: each running cloak casts its spell on the actors near its holder.
    struct CloakPulses {
        let coordinator: MagicCoordinator
    }

    /// Turns each casting hand's changes into the cues the behaviour graph hears.
    struct CastingCueTracker {
        let coordinator: MagicCoordinator
    }

    /// The magic facts that condition functions read.
    struct ConditionReads {
        let coordinator: MagicCoordinator
    }

    /// The enchanting table: learning, disenchanting and enchanting items.
    struct EnchantingTable {
        let coordinator: MagicCoordinator
    }

    /// The player's enchanting state: learnt bases, made items, and disenchanting.
    struct EnchantingRecords {
        let coordinator: MagicCoordinator
    }

    /// Detect Life paint, Telekinesis and Grab Actor holds, and Guide trails.
    struct HoldEffects {
        let coordinator: MagicCoordinator
    }

    /// The one-line outcomes the menus show.
    public struct MenuLines {
        let coordinator: MagicCoordinator
    }

    /// The arcane enchanter's menu: what it offers and its two actions.
    public struct Enchanter {
        let coordinator: MagicCoordinator
    }

    /// The spells and powers the Magic menu lists.
    public struct MagicMenu {
        let coordinator: MagicCoordinator
    }

    /// The readout panels' snapshots and forced actions.
    struct ControlPanels {
        let coordinator: MagicCoordinator
    }

    /// The Magic Effects readout and its actions.
    struct EffectsPanel {
        let coordinator: MagicCoordinator
    }

    /// The perk entry points magic reads.
    struct PerkEffects {
        let coordinator: MagicCoordinator
    }

    /// The effects an actor's race adds to a spell hit.
    struct RaceEffects {
        let coordinator: MagicCoordinator
    }

    /// Recharging an enchanted weapon from a soul gem.
    struct WeaponRecharge {
        let coordinator: MagicCoordinator
    }

    /// Runes on the ground and their detonation.
    struct RunePlacement {
        let coordinator: MagicCoordinator
    }

    /// Voicing shouts: the press, the words and the cooldown.
    public struct ShoutVoice {
        let coordinator: MagicCoordinator
    }

    /// Reading spell tomes and skill books.
    struct SpellTomes {
        let coordinator: MagicCoordinator
    }

    /// The clocks Slow Time splits.
    struct SlowTimeClock {
        let coordinator: MagicCoordinator
    }

    /// Soul Trap, soul gems and Soul Siphon.
    public struct SoulTrapping {
        let coordinator: MagicCoordinator
    }

    /// Summoned and reanimated actors, and their fading.
    struct SummonCommands {
        let coordinator: MagicCoordinator
    }

    /// Wards: absorbing spell damage and breaking.
    struct WardShields {
        let coordinator: MagicCoordinator
    }

    /// The world archetypes: light, race change, bound and enhanced weapons.
    public struct WorldArchetypeActions {
        let coordinator: MagicCoordinator
    }

    /// Bound weapons and weapon enhancement, and when the world refuses them.
    struct WeaponArchetypes {
        let coordinator: MagicCoordinator
    }

    /// The shout readout's snapshot.
    struct ShoutReadout {
        let coordinator: MagicCoordinator
    }

    /// The enchanting readout's snapshot.
    struct EnchantingReadout {
        let coordinator: MagicCoordinator
    }
}

extension MagicCoordinator {
    public var frameStep: FrameStep {
        FrameStep(coordinator: self)
    }

    public var itemUse: ItemUse {
        ItemUse(coordinator: self)
    }

    public var weaponEnchantments: WeaponEnchantments {
        WeaponEnchantments(coordinator: self)
    }

    /// The frame step: effects, casting, and the commands they leave for the app.
    public struct FrameStep {
        let coordinator: MagicCoordinator
    }

    /// Consuming magic items, granting authored spells, and dispelling.
    public struct ItemUse {
        let coordinator: MagicCoordinator
    }

    /// Weapon and worn enchantments, poisons, and their readouts.
    public struct WeaponEnchantments {
        let coordinator: MagicCoordinator
    }

    /// Poison doses landing on their target.
    enum PoisonDoses {}

    /// The world the caster runtime casts in, and the staffs it charges. A class,
    /// because the runtime holds both weakly; the coordinator keeps it alive.
    final class CasterBridge: CasterWorld, StaffCharging {
        unowned let coordinator: MagicCoordinator

        init(coordinator: MagicCoordinator) {
            self.coordinator = coordinator
        }
    }

    /// The staffs actors hold, read from their equipment.
    struct HeldStaves {
        let coordinator: MagicCoordinator
    }
}

extension MagicCoordinator {
    var heldStaves: HeldStaves {
        HeldStaves(coordinator: self)
    }
}
