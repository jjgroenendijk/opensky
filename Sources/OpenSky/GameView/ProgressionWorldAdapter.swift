// App side of `PerkCoordinator` and `ProgressionCoordinator`: builds their
// runtimes from the provider and answers both ports from the session systems.
// The rules live in the coordinators (docs/engine/coordinators.md).

import OpenSkyActors
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyWorld
import OpenSkyWorldState

/// Answers `PerkWorld` and `ProgressionWorld` from the session systems `game` owns.
final class ProgressionWorldAdapter {
    unowned let game: GameViewController

    init(game: GameViewController) {
        self.game = game
    }

    /// After the caster, which folds the spell-cost entry point through its
    /// own copy of the runtime.
    func wirePerks(provider: any WorldDataProviding) {
        guard let store = (provider as? ProgressionDataProviding)?.perkStore else { return }
        var runtime = PerkRuntime(
            store: game.worldState, perks: store, conditionRegistry: .standard
        )
        runtime.conditions = ConditionContext(globals: game.runtimeStateGlobalResolution())
        game.perks.wire(
            runtime,
            baselines: (provider as? ActorValueDataProviding)?.actorValueBaselines?.resolver
                .map(ActorPerkBaselineResolver.init(actorValues:)),
            pluginName: (provider as? MagicDataProviding)?.magicItemPluginName
        )
    }

    /// After `wireActorValues`, which every skill write goes through, and after
    /// the world items, which the worn-armor read uses.
    func wireSkills(provider: any WorldDataProviding) {
        guard
            let values = game.actorValues.runtime,
            let progression = provider as? ProgressionDataProviding,
            let information = progression.actorValueInformation
        else { return }
        game.progression.wireSkills(
            values: values,
            information: information,
            settings: progression.skillAdvancementSettings
        )
    }

    /// After `wirePerks` and `wireSkills`: the spend validator reads the perk
    /// runtime, and the skill runtime banks into this one.
    func wireProgression(provider: any WorldDataProviding) {
        guard let values = game.actorValues.runtime else { return }
        let progression = provider as? ProgressionDataProviding
        game.progression.wireLeveling(
            values: values,
            settings: progression?.characterLevelSettings ?? .documentedDefaults,
            perkStore: progression?.perkStore,
            information: progression?.actorValueInformation
        )
    }

    /// The player's own holder, or a resident actor's.
    private func inventoryHolder(of key: ReferenceKey) -> InventoryHolder? {
        if key == .player {
            return .player
        }
        guard
            let streamer = game.streamer,
            let actor = streamer.referenceEntry(key: key)?.placedActor
        else { return nil }
        return InventoryHolder(
            key: key, owner: .actor(base: actor.base), cell: streamer.cellLocation(of: key)
        )
    }
}

extension ProgressionWorldAdapter: PerkWorld {
    func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        game.actorWorld.actorValueHolder(for: key)
    }

    func actorValue(at index: Int32, on holder: ActorValueHolder) -> Float? {
        game.actorValues.runtime?.value(at: index, on: holder)
    }

    func perksChanged(_ runtime: PerkRuntime) {
        game.magic.caster?.perks = runtime
    }

    func reconcileAbilities(on holder: ActorValueHolder, perks: PerkRuntime) {
        guard let spells = game.magic.caster?.spellbook.spells else { return }
        _ = game.magic.withEffects { effects in
            PerkAbilityApplication.reconcile(
                on: holder, perks: perks, spells: spells, using: &effects
            )
        }
    }
}

extension ProgressionWorldAdapter: ProgressionWorld {
    /// Only equipped armor counts; clothing trains neither armor skill. The
    /// item index is the melee runtime's, to avoid a second decode.
    func wornArmor(of key: ReferenceKey) -> WornArmorProfile {
        guard
            let equipment = game.inventory.equipment,
            let items = game.combat.items,
            let holder = inventoryHolder(of: key)
        else { return .none }
        var heavy = 0
        var light = 0
        for item in equipment.equipped(on: holder) {
            switch items.armorType(item) {
            case .heavy: heavy += 1
            case .light: light += 1
            case .clothing, nil: continue
            }
        }
        return WornArmorProfile(heavyPieces: heavy, lightPieces: light)
    }

    func conditionContext() -> ConditionContext {
        game.runtimeStateConditionContext()
    }

    func conditionText(_ condition: Condition) -> String {
        RuntimeStateConditionRunner.describe(condition, registry: .standard)
    }
}
