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
    func wireEffects(provider: any WorldDataProviding, renderer: Renderer) {
        guard
            let values = game.actorValues.runtime,
            let magic = provider as? MagicDataProviding,
            let store = magic.magicEffectStore,
            let pluginName = magic.magicItemPluginName
        else { return }
        let coordinator = game.magic
        coordinator.attach(world: self)
        coordinator.wireEffects(
            values: values, store: store, pluginName: pluginName, conditionRegistry: .standard
        )
        // Chained after regeneration and the Papyrus VM, on the same delta.
        let advanceOthers = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak coordinator] delta in
            advanceOthers?(delta)
            coordinator?.advanceEffects(delta: delta)
        }
    }

    /// After `wireEffects`, because a cast applies its effects through it.
    func wireCasting(provider: any WorldDataProviding, renderer: Renderer) {
        guard
            let values = game.actorValues.runtime,
            let magic = provider as? MagicDataProviding,
            let spells = magic.spellStore,
            let equipSlots = magic.equipSlotStore
        else { return }
        let coordinator = game.magic
        coordinator.attach(world: self)
        coordinator.wireCasting(
            spellbook: SpellbookRuntime(
                store: game.worldState,
                spells: spells,
                equipSlots: equipSlots,
                equipment: game.worldItems.equipment
            ),
            values: values,
            spellPluginName: magic.magicItemPluginName,
            baselines: (provider as? ActorValueDataProviding)?.actorValueBaselines?.resolver
                .map { ActorSpellBaselineResolver(actorValues: $0) }
        )
        // `onFrame`, beside melee: a cast is timed against the rendered frame.
        renderer.onFrame.add { [weak coordinator, weak renderer] _ in
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

    func wireEnchantments(provider: any WorldDataProviding) {
        game.magic.attach(world: self)
        game.magic.wireEnchantments(store: (provider as? MagicDataProviding)?.enchantmentStore)
    }
}

extension MagicWorldAdapter: MagicWorld {
    var gameDaysPassed: Float {
        game.renderer?.gameClock.daysPassed ?? 0
    }

    var inventory: (any InventoryAccess)? {
        game.worldItems.runtime?.inventory
    }

    var equipment: (any EquipmentAccess)? {
        game.worldItems.equipment
    }

    @discardableResult
    func reportSkillUse(_ use: SkillUseEvent) -> Float {
        game.reportSkillUse(use)
    }

    func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        game.actorValueHolder(for: key)
    }

    func regeneratingHolders() -> [ActorValueHolder] {
        game.regeneratingHolders()
    }

    func nearestActorValueHolder() -> ActorValueHolder? {
        game.nearestActorValueHolder()
    }

    func residentActorKeys() -> [ReferenceKey] {
        game.combatActors().map(\.key)
    }

    func actorName(_ holder: ActorValueHolder) -> String {
        game.name(ofActorValueHolder: holder)
    }

    func itemName(_ item: FormID) -> String {
        game.name(of: item)
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
}
