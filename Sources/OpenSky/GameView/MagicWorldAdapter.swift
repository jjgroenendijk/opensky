// App side of `MagicCoordinator`: builds its runtimes from the provider, steps
// them from the renderer's frame hooks, and answers `MagicWorld` from the
// session systems. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldState

/// Answers `MagicWorld` from the session systems `game` owns.
final class MagicWorldAdapter {
    unowned let game: GameViewController

    init(game: GameViewController) {
        self.game = game
    }

    /// After `wireActorValues`, because every effect writes an actor value. A
    /// provider without an MGEF index leaves the runtime nil.
    func wireEffects(provider: WorldDataStores, renderer: Renderer) {
        guard
            let values = game.actorValues.runtime,
            let store = provider.magicEffectStore,
            let pluginName = provider.magicItemPluginName
        else { return }
        let coordinator = game.magic
        coordinator.attach(world: self)
        coordinator.wireEffects(
            values: values, store: store, pluginName: pluginName, conditionRegistry: .standard
        )
        // Chained after regeneration and the Papyrus VM, on the same delta.
        let worldTick = renderer.session.worldTick
        worldTick.register(.magicEffects) { [weak coordinator, weak renderer] delta in
            coordinator?.advanceEffects(delta: delta)
            renderer?.session.isPlayerParalysed = coordinator?.influence(of: .player)
                .isParalysed ?? false
        }
    }

    /// After `wireEffects`, because a cast applies its effects through it.
    func wireCasting(provider: WorldDataStores, renderer: Renderer) {
        guard
            let values = game.actorValues.runtime,
            let spells = provider.spellStore,
            let equipSlots = provider.equipSlotStore
        else { return }
        let coordinator = game.magic
        coordinator.attach(world: self)
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
        renderer.session.frameSteps.register(.spellCasting) { [weak coordinator, weak renderer] _ in
            guard let coordinator, let renderer else { return }
            let locomotion = renderer.locomotion
            coordinator.advanceCasting(
                CastingIntent(
                    leftHeld: locomotion.meleeIntent.block,
                    rightHeld: locomotion.archeryIntent.drawing,
                    deltaTime: locomotion.archeryIntent.deltaTime
                ),
                isPlayerControlled: renderer.movementMode.isPlayerControlled
            )
        }
    }

    func wireEnchantments(provider: WorldDataStores) {
        game.magic.attach(world: self)
        game.magic.magicTexts = MagicTexts
            .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
        game.magic.spellCostSettings = SpellCostSettings.resolve(store: provider.gameSettings)
        game.magic.wireEnchantments(store: provider.enchantmentStore)
    }
}

extension MagicWorldAdapter: MagicWorld {
    var gameDaysPassed: Float {
        game.renderer?.gameClock.daysPassed ?? 0
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

    /// The race the actor-value baseline derives from, so a session cannot
    /// have one race's attributes and another race's powers.
    func playerRaceSpells() -> [FormID] {
        guard
            let baselines = game.actorValues.runtime?.baselines,
            let raceID = baselines.playerRace,
            let race = baselines.resolver?.races[raceID.rawValue]
        else { return [] }
        return race.spells
    }

    func conditionText(
        of function: UInt16,
        parameter: UInt32,
        in context: ConditionContext
    ) -> String {
        ConditionProbe.text(of: function, parameter1: parameter, in: context)
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
