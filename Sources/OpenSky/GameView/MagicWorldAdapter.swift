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
    var magic: MagicCoordinator { get }
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

    /// After `wireActorValues`, because every effect writes an actor value. A
    /// provider without an MGEF index leaves the runtime nil.
    func wireEffects(provider: WorldDataStores, gameSession: GameSession) {
        guard
            let values = game.actorValues.runtime,
            let store = provider.magicEffectStore,
            let pluginName = provider.magicItemPluginName
        else { return }
        let coordinator = game.magic
        coordinator.wireEffects(
            values: values, store: store, pluginName: pluginName, conditionRegistry: .standard
        )
        // Chained after regeneration and the Papyrus VM, on the same delta.
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

    /// After `wireEffects`, because a cast applies its effects through it.
    func wireCasting(provider: WorldDataStores, gameSession: GameSession) {
        guard
            let values = game.actorValues.runtime,
            let spells = provider.spellStore,
            let equipSlots = provider.equipSlotStore
        else { return }
        let coordinator = game.magic
        coordinator.wireCasting(
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
        // A frame step, beside melee: a cast is timed against the rendered frame.
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

    func wireEnchantments(provider: WorldDataStores) {
        game.magic.magicTexts = MagicTexts
            .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
        game.magic.castNotices = game.mapWorld.settingTexts()
        game.magic.spellCostSettings = SpellCostSettings.resolve(store: provider.gameSettings)
        game.magic.soulTrapSettings = SoulTrapSettings.resolve(store: provider.gameSettings)
        game.magic.holdSettings = MagicHoldSettings.resolve(store: provider.gameSettings)
        game.magic.enchantingSettings = EnchantingSettings.resolve(store: provider.gameSettings)
        game.magic.soulTexts = SoulTexts
            .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
        game.magic.wireEnchantments(store: provider.enchantmentStore)
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
