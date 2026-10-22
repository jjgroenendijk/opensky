// The shell of the magic domain: owns the active-effect runtime, the caster
// runtime and the enchantment index, steps them, and is the world the cast loop
// resolves through. The rules live in `MagicCore`. See docs/engine/coordinators.md.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

/// Owns the magic runtimes and reads the world through `MagicWorld`.
@MainActor
public final class MagicCoordinator {
    /// Nil until `wireEffects`. A value over a shared store, so every change
    /// goes through `withEffects`.
    public private(set) var effects: ActiveEffectRuntime?
    /// Nil until `wireCasting`.
    public private(set) var caster: CasterRuntime?
    /// The plugin every magic item's EFID links are relative to.
    public private(set) var pluginName = ""
    /// The plugin an actor's `SPLO` links are relative to.
    public private(set) var spellPluginName: String?
    /// What the most recent landed spell applied. Nil until one lands.
    public private(set) var lastHit: SpellHitReport?
    /// Called after every spell hit that reached someone, for the visual and
    /// image-space hooks. One observer: the effects adapter.
    public var onSpellHit: ((SpellHitEvent) -> Void)?
    /// The ENCH index. Setting it drops the cached profiles derived from it.
    public private(set) var enchantmentStore: EnchantmentStore? {
        didSet { profiles.invalidate() }
    }

    let world: any MagicWorld
    /// What the effects asked of the app. A frame step returns and empties it.
    var pendingCommands: [MagicCommand] = []
    /// Takes `CAST`.
    public weak var storyEvents: (any StoryEventReporting)?
    /// Hears every cast, as spell then caster, for the `OnSpellCast` event.
    public var onSpellCast: ((ReferenceKey, ReferenceKey) -> Void)?
    /// The spell words the spellcasting panel shows.
    public var magicTexts = MagicTexts.vanilla
    public var castNotices = GameSettingTexts<CastNoticeText>.vanilla
    /// The hands pressed last frame, so a press during a shout is refused once.
    var castPressed: Set<SpellHand> = []
    public var spellCostSettings = SpellCostSettings.vanilla {
        didSet { caster?.costSettings = spellCostSettings }
    }

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
    public var spellDefenceRoll: () -> Float = { Float.random(in: 0 ..< 100) }
    public var soulTrapSettings = SoulTrapSettings.vanilla
    public var soulTexts = SoulTexts.vanilla
    public internal(set) var lastSoulTrap: SoulTrapOutcome?
    public internal(set) var lastRecharge: RechargeOutcome?
    public internal(set) var lastEnchanting = EnchantingOutcome.idle
    /// Every SHOU in the load order, by key. Empty until `wireShouts`.
    public internal(set) var shouts: [ReferenceKey: ResolvedShout] = [:]
    public var shoutSettings = ShoutSettings.vanilla
    public internal(set) var shoutMachine = ShoutMachine()
    var wasShoutHeld = false
    /// Seconds the panel's Shout button still holds the key.
    var panelShoutHold: Float?
    /// The shout the machine is voicing, fixed at the press.
    var voicedShout: ReferenceKey?
    public internal(set) var lastShout = ShoutOutcome.idle
    /// Each casting hand as the cues saw it last frame; an idle hand is left out.
    var castingViews: [CastSlot: CastingHandView] = [:]
    public internal(set) var releaseLatch = SpellReleaseLatch()
    var wasWeaponsDrawn: Bool?
    public internal(set) var castingCueCount = 0
    public internal(set) var lastCastingCue: String?
    /// Runes waiting on the ground, oldest first. Not saved.
    public internal(set) var runes: [PlacedRune] = []
    public var runeSettings = RuneSettings.vanilla
    public internal(set) var detonatedRunes = 0
    /// Summoned and reanimated actors, oldest first. Not saved.
    public internal(set) var commanded: [CommandedActor] = []
    /// Where each caster aimed its last target-location summon.
    var summonPoints: [ReferenceKey: SIMD3<Float>] = [:]
    var profiles = ItemEnchantmentProfileCache()
    var spellBaselines: ActorSpellBaselineResolver?
    /// Actors whose authored spell list was granted, so it happens once.
    var grantedActors: Set<ReferenceKey> = []
    /// An index into the player's known spells. Clamped on read.
    var selection = 0
    public internal(set) var lastEffectAction = MagicEffectActionOutcome.idle
    public internal(set) var lastCastingAction = CastingActionOutcome.idle

    public init(world: any MagicWorld) {
        self.world = world
    }

    public func wireEffects(
        values: any ActorValueAccess,
        store: MagicEffectStore,
        pluginName: String,
        conditionRegistry: ConditionFunctionRegistry
    ) {
        effects = ActiveEffectRuntime(
            values: values,
            effects: store,
            conditionRegistry: conditionRegistry
        )
        self.pluginName = pluginName
        wireArchetypeLookups()
    }

    public func wireCasting(
        spellbook: SpellbookRuntime,
        values: any ActorValueAccess,
        spellPluginName: String?,
        baselines: ActorSpellBaselineResolver?
    ) {
        let runtime = CasterRuntime(spellbook: spellbook, values: values, world: self)
        runtime.costSettings = spellCostSettings
        caster = runtime
        self.spellPluginName = spellPluginName
        spellBaselines = baselines
    }

    public func wireEnchantments(store: EnchantmentStore?) {
        enchantmentStore = store
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
            performWorldActions()
        }
        return try body(&runtime)
    }

    /// Takes the world actions the runtime queued, leaving none.
    func takeWorldActions() -> [MagicWorldAction] {
        guard var runtime = effects, !runtime.worldActions.isEmpty else { return [] }
        let actions = runtime.worldActions
        runtime.worldActions = []
        effects = runtime
        return actions
    }

    /// Whole effect steps for the delta this frame simulated, over the player
    /// and the resident actors. A menu-paused frame delivers delta 0.
    public func advanceEffects(delta: Float) -> [MagicCommand] {
        guard var runtime = effects else { return takeCommands() }
        let holders = world.regeneratingHolders()
        let scales = timeScales
        if scales.isSlowed {
            // The player's effects run on the player's clock, so Slow Time ends on time.
            let split = Dictionary(grouping: holders) { $0.key == .player }
            runtime.advance(delta: delta, accumulator: &accumulator, over: split[false] ?? [])
            runtime.advance(
                delta: delta * scales.player / scales.world,
                accumulator: &playerAccumulator,
                over: split[true] ?? []
            )
        } else {
            runtime.advance(delta: delta, accumulator: &accumulator, over: holders)
            playerAccumulator = accumulator
        }
        effects = runtime
        performWorldActions()
        maintainCarriedEffects(delta: delta)
        pulseCloaks(delta: delta)
        return takeCommands()
    }

    /// Returns and empties what the effects asked of the app. A command raised
    /// outside a frame step, such as by a script, also leaves with the next one.
    public func takeCommands() -> [MagicCommand] {
        defer { pendingCommands = [] }
        return pendingCommands
    }

    /// One frame of casting. A frame in a menu or in free-fly charges nothing
    /// for the player, but NPC casts still advance. `events` are the player graph's.
    public func advanceCasting(
        _ intent: CastingIntent,
        isPlayerControlled: Bool,
        events: [String] = [],
        weaponsDrawn: Bool? = nil
    ) -> [MagicCommand] {
        guard let caster else { return takeCommands() }
        let playerIntent = isPlayerControlled
            ? refusingCastsDuringShout(latched(intent, events: events)) : .still
        caster.acceptFrame(playerIntent, on: .player)
        for failure in caster.takePlayerFailures() {
            if let text = CastNoticeText.notice(for: failure) {
                pendingCommands.append(.notice(castNotices[text]))
            }
        }
        advanceActorCasts(delta: intent.deltaTime)
        advanceRunes()
        advanceCommanded()
        advanceCastingCues(weaponsDrawn: weaponsDrawn)
        return takeCommands()
    }

    /// Every NPC cast in flight, charged on the player's clock.
    func advanceActorCasts(delta: Float) {
        guard let caster, delta > 0 else { return }
        for key in caster.castingActors where key != .player {
            guard let holder = world.actorValueHolder(for: key) else { continue }
            caster.advance(delta: delta, on: holder)
        }
    }

    /// Whether `hand` holds a readied spell, which routes its button to the
    /// cast loop instead of to melee.
    public func hasReadiedSpell(in hand: SpellHand) -> Bool {
        caster?.spellbook.state(of: .player).spell(in: hand) != nil
    }

    /// Consumes `item` from the player and applies it to the player. The menu
    /// and the panel both call this, and show the line of the outcome it returns.
    @discardableResult
    public func consumeMagicItem(_ item: FormID) -> MagicEffectActionOutcome {
        guard effects != nil, let inventory = world.inventory else {
            return recordEffect(.unavailable)
        }
        let name = inventory.baselines.items.definition(item)?.editorID ?? item.description
        do {
            let plugin = pluginName
            let outcome = try withEffects { runtime in
                try runtime.consume(
                    item, from: .player, on: .player, inventory: inventory, fromPlugin: plugin
                ) { entries, source in
                    self.perkScaledPotion(
                        entries, of: source, fromPlugin: plugin, drinker: .player
                    )
                }
            }
            if outcome?.kind == .ingredient {
                world.playerAteIngredient(item)
            }
            return recordEffect(.consumed(item: name, outcome))
        } catch {
            return recordEffect(.consumeFailed(item: name, reason: String(describing: error)))
        }
    }

    @discardableResult
    func recordEffect(_ outcome: MagicEffectActionOutcome) -> MagicEffectActionOutcome {
        lastEffectAction = outcome
        return outcome
    }

    @discardableResult
    func recordCasting(_ outcome: CastingActionOutcome) -> CastingActionOutcome {
        lastCastingAction = outcome
        return outcome
    }

    /// Grants `holder`'s authored spell list on first ask, so townsfolk who
    /// never fight write no spellbook into the save.
    public func grantAuthoredSpells(to holder: ActorValueHolder) {
        guard
            let caster,
            let spellBaselines,
            let spellPluginName,
            !grantedActors.contains(holder.key)
        else { return }
        grantedActors.insert(holder.key)
        let baseline = spellBaselines.baseline(for: holder.subject)
        caster.spellbook.grant(
            caster.spellbook.resolve(baseline.all, fromPlugin: spellPluginName),
            to: holder
        )
        reconcileAbilities(on: holder)
    }

    /// The carried items, in FormID order, that `transform` maps to a value.
    func carriedItems<Value>(_ transform: (ItemDefinitionStore, FormID) -> Value?) -> [Value] {
        guard let inventory = world.inventory else { return [] }
        let items = inventory.baselines.items
        return inventory.inventory(of: .player).stacks
            .map(\.item)
            .sorted { $0.rawValue < $1.rawValue }
            .compactMap { transform(items, $0) }
    }
}

extension MagicCoordinator: CasterWorld {
    public var castingGameDay: Int32 {
        MagicCore.gameDay(world.gameDaysPassed)
    }

    @discardableResult
    public func reportSkillUse(_ use: SkillUseEvent) -> Float {
        world.reportSkillUse(use)
    }

    public func applyCastEffects(
        _ entries: [MagicItemEffect],
        fromPlugin pluginName: String,
        source: ActiveEffectSource,
        caster: ReferenceKey,
        on target: ActorValueHolder
    ) -> Int {
        let scaled = source.kind == .spell
            ? perkScaled(entries, of: source.record, caster: caster, on: target.key)
            : entries
        let isDualCast = self.caster?.isApplyingDualCast == true
        let stored = withEffects { runtime in
            runtime.application.isDualCast = isDualCast
            defer { runtime.application = MagicApplicationContext() }
            return runtime.apply(
                scaled, fromPlugin: pluginName, source: source, caster: caster, on: target
            )
        }
        return stored?.count ?? 0
    }

    @discardableResult
    public func fireSpellProjectile(_ payload: SpellPayload) -> Bool {
        world.fireSpellProjectile(payload)
    }

    public func aimedSpellTarget(within range: Float, for caster: ReferenceKey) -> SpellAim {
        world.aimedSpellTarget(within: range, for: caster)
    }

    /// Casting breaks the caster's invisibility. The wiki says only the player's
    /// casts count as a story event.
    public func spellWasCast(_ spell: ReferenceKey, by caster: ReferenceKey) {
        onSpellCast?(spell, caster)
        breakInvisibility(of: caster)
        guard caster == .player, let storyEvents else { return }
        storyEvents.reportStoryEvent(.castMagic(
            caster: caster,
            target: aimedSpellTarget(within: 0, for: caster).target,
            location: nil,
            spell: StoryEventData.form(of: spell)
        ))
    }

    /// A projectile hit and a direct cast take this one path, so the effects
    /// panel's tally counts both.
    @discardableResult
    public func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        let holders = residentHolders(of: hit.targets)
        guard
            let report = withEffects({ runtime in
                runtime.application.isDualCast = hit.payload.isDualCast
                defer { runtime.application = MagicApplicationContext() }
                return SpellHitApplication
                    .apply(
                        hit, holders: holders, using: &runtime, defences: spellHitDefences()
                    ) { entries, target in
                        self.perkScaled(
                            entries, of: hit.payload.spell, caster: hit.payload.caster, on: target
                        )
                    }
            })
        else { return .none }
        lastHit = report
        breakWards(report.brokenWards)
        if !hit.targets.isEmpty, let onSpellHit, let store = effects?.effects {
            onSpellHit(SpellHitEvent(hit: hit, links: store.hitEffectLinks(of: hit.payload)))
        }
        return report
    }

    /// The holder of each target still resident. A target that left is absent.
    func residentHolders(of targets: [SpellHitTarget]) -> [ReferenceKey: ActorValueHolder] {
        var holders: [ReferenceKey: ActorValueHolder] = [:]
        for target in targets {
            holders[target.key] = world.actorValueHolder(for: target.key)
        }
        return holders
    }
}

extension MagicCoordinator {
    /// A hand pressed while the player shouts does not begin its cast, and a new press
    /// says why. A cast already running is left to finish.
    func refusingCastsDuringShout(_ intent: CastingIntent) -> CastingIntent {
        var refused = intent
        let shouting = !shoutMachine.isIdle
        for hand in SpellHand.allCases {
            let pressed = intent.isHeld(hand)
            defer {
                if pressed {
                    castPressed.insert(hand)
                } else {
                    castPressed.remove(hand)
                }
            }
            guard
                shouting, pressed, hasReadiedSpell(in: hand),
                !(caster?.phase(of: hand).isCasting ?? false)
            else { continue }
            if !castPressed.contains(hand) {
                pendingCommands.append(.notice(castNotices[.castWhileShouting]))
            }
            switch hand {
            case .left: refused.leftHeld = false
            case .right: refused.rightHeld = false
            }
        }
        return refused
    }
}
