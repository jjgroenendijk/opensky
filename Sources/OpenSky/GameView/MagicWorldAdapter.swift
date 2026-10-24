// App side of `MagicCoordinator`: builds its runtimes from the provider, steps
// them from the renderer's frame hooks, and answers `MagicWorld` from the
// session systems. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldState

/// What `MagicWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol MagicWorldHost: AnyObject {
    var actorValues: ActorValueCoordinator { get }
    var actorWorld: ActorWorldAdapter { get }
    var combat: CombatCoordinator { get }
    var effectsWorld: EffectsWorldAdapter { get }
    var factions: FactionCoordinator { get }
    var hazards: HazardCoordinator { get }
    var hazardWorld: HazardWorldAdapter { get }
    var hud: HUDCoordinator { get }
    var inventory: InventoryCoordinator { get }
    var magic: MagicCoordinator { get set }
    var mapWorld: MapWorldAdapter { get }
    var menuWorld: MenuWorldAdapter { get }
    var messages: MessageCoordinator { get }
    var perks: PerkCoordinator { get }
    var storyWorld: StoryWorldAdapter { get }
    var progression: ProgressionCoordinator { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    var scripts: ScriptCoordinator { get }
    var streamer: CellStreamer? { get }
    var worldData: WorldDataStores? { get }
    var worldState: WorldStateStore { get }
}

/// Answers `MagicWorld` from the session systems `game` owns.
final class MagicWorldAdapter {
    unowned let game: any MagicWorldHost
    /// The NPCs a Grab Actor effect holds through the ridden-actor hold.
    var grabbedActors: Set<ReferenceKey> = []

    init(game: any MagicWorldHost) {
        self.game = game
    }

    /// After `wireActorValues`, because every effect writes an actor value, and after
    /// `wireWorldItems`, because the spellbook reads the equipment.
    func wireMagic(provider: WorldDataStores, gameSession: GameSession) {
        let coordinator = MagicCoordinator(
            world: self, data: sessionData(provider: provider), storyEvents: game.storyWorld
        )
        game.magic = coordinator
        if coordinator.effects != nil {
            registerEffects(coordinator, gameSession: gameSession)
        }
        if coordinator.caster != nil {
            registerCasting(coordinator, gameSession: gameSession)
        }
    }

    private func sessionData(provider: WorldDataStores) -> MagicSessionData {
        let settings = provider.gameSettings
        var data = MagicSessionData()
        if
            let values = game.actorValues.runtime,
            let store = provider.magicEffectStore,
            let pluginName = provider.magicItemPluginName
        {
            data.effects = MagicEffectsData(
                values: values, store: store, pluginName: pluginName, conditionRegistry: .standard
            )
        }
        if
            let values = game.actorValues.runtime,
            let spells = provider.spellStore,
            let equipSlots = provider.equipSlotStore
        {
            data.casting = MagicCastingData(
                spellbook: SpellbookRuntime(
                    store: game.worldState,
                    spells: spells,
                    equipSlots: equipSlots,
                    equipment: game.inventory.equipment
                ),
                values: values,
                spellPluginName: provider.magicItemPluginName,
                baselines: provider.actorValueBaselines?.resolver
                    .map { ActorSpellBaselineResolver(actorValues: $0) }
            )
        }
        data.enchantments = provider.enchantmentStore
        data.shouts = provider.shoutStore
        data.rules.spellCost = SpellCostSettings.resolve(store: settings)
        data.rules.soulTrap = SoulTrapSettings.resolve(store: settings)
        data.rules.holds = MagicHoldSettings.resolve(store: settings)
        data.rules.enchanting = EnchantingSettings.resolve(store: settings)
        data.rules.shouts = ShoutSettings.resolve(store: settings)
        data.rules.runes = RuneSettings.resolve(store: settings)
        data.texts.magic = MagicTexts.resolve(store: settings) { [game] in game.mapWorld.text($0) }
        data.texts.castNotices = game.mapWorld.settingTexts()
        data.texts.souls = SoulTexts.resolve(store: settings) { [game] in game.mapWorld.text($0) }
        return data
    }

    /// Chained after regeneration and the Papyrus VM, on the same delta.
    private func registerEffects(_ coordinator: MagicCoordinator, gameSession: GameSession) {
        let worldTick = gameSession.worldTick
        worldTick.register(.magicEffects) { [weak self, weak coordinator, weak gameSession] delta in
            self?.run(coordinator?.advanceEffects(delta: delta) ?? [])
            self?.publishMagicLights()
            gameSession?.isPlayerParalysed = coordinator?.influence(of: .player)
                .isParalysed ?? false
            let scales = coordinator?.timeScales ?? .normal
            gameSession?.magicTimeScale = scales.world
            gameSession?.playerTimeScale = scales.player
        }
    }

    /// A frame step, beside melee: a cast is timed against the rendered frame.
    private func registerCasting(_ coordinator: MagicCoordinator, gameSession: GameSession) {
        let frameSteps = gameSession.frameSteps
        frameSteps.register(.spellCasting) { [weak self, weak coordinator, weak gameSession] _ in
            guard let coordinator, let gameSession else { return }
            let locomotion = gameSession.locomotion
            let isPlayerControlled = gameSession.movementMode.isPlayerControlled
            let delta = locomotion.archeryIntent.deltaTime
            let events = locomotion.graphEvents.drain(locomotion.magicEventConsumer)
            let commands = coordinator.advanceCasting(
                CastingIntent(
                    leftHeld: locomotion.meleeIntent.block,
                    rightHeld: locomotion.archeryIntent.drawing,
                    deltaTime: delta
                ),
                isPlayerControlled: isPlayerControlled,
                events: events,
                weaponsDrawn: self?.game.combat.melee?.state.drawState.isWeaponInHand
            )
            self?.run(commands)
            self?.run(coordinator.advanceShout(
                held: locomotion.isShoutHeld,
                delta: delta,
                events: events,
                isPlayerControlled: isPlayerControlled
            ))
        }
    }

    /// A hit from outside the magic frame steps runs its commands at once, so the
    /// hit effects and the ragdoll's push land in the same frame as the damage.
    @discardableResult
    func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        let report = game.magic.applySpellHit(hit)
        run(game.magic.takeCommands())
        return report
    }

    func noteSpellCast(_ spell: ReferenceKey, by caster: ReferenceKey) {
        game.scripts.runtime?.queueSpellCast(spell, by: caster)
    }
}

extension MagicWorldAdapter: MagicWorld {
    var gameDaysPassed: Float {
        game.gameSession?.gameClock.daysPassed ?? 0
    }

    var inventory: (any InventoryAccess)? {
        game.inventory.runtime?.inventory
    }

    var equipment: (any EquipmentAccess)? {
        game.inventory.equipment
    }

    @discardableResult
    func reportSkillUse(_ use: SkillUseEvent) -> Float {
        game.progression.reportSkillUse(game.combat.adjustingForDifficulty(use))
    }

    func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        game.actorWorld.actorValueHolder(for: key)
    }

    func regeneratingHolders() -> [ActorValueHolder] {
        game.actorWorld.regeneratingHolders()
    }

    func nearestActorValueHolder() -> ActorValueHolder? {
        game.actorWorld.nearestActorValueHolder()
    }

    func residentActorKeys() -> [ReferenceKey] {
        game.actorWorld.combatActors().map(\.key)
    }

    func actorName(_ holder: ActorValueHolder) -> String {
        ActorValueCoordinator.name(of: holder)
    }

    func itemName(_ item: FormID) -> String {
        game.inventory.name(of: item)
    }

    func conditionText(
        of function: UInt16,
        parameter: UInt32,
        in context: ConditionContext
    ) -> String {
        ConditionProbe.text(of: function, parameter1: parameter, in: context)
    }

    func playerAteIngredient(_ item: FormID) {
        game.inventory.learnEatenIngredient(item)
    }

    func postNotification(_ text: String) {
        _ = game.messages.postNotification(text)
    }

    func raiseSkillFromBook(_ skill: Int32, points: Int) -> Int {
        (0 ..< max(0, points)).reduce(0) { raised, _ in
            raised + (game.progression.incrementSkill(skill) ? 1 : 0)
        }
    }

    func perkModified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> Float {
        game.perks.modified(
            value,
            at: entryPoint,
            on: key,
            subjects: { _ in subjects },
            seams: seams
        )
    }
}
