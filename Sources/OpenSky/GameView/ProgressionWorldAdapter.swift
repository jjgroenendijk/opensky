// App side of `PerkCoordinator` and `ProgressionCoordinator`: builds their
// runtimes from the provider and answers both ports from the session systems.
// The rules live in the coordinators (docs/engine/coordinators.md).

import Foundation
import OpenSkyActors
import OpenSkyCells
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuests
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldState

/// What `ProgressionWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol ProgressionWorldHost: AnyObject {
    var actorValues: ActorValueCoordinator { get }
    var actorWorld: ActorWorldAdapter { get }
    var combat: CombatCoordinator { get }
    var dialogueWorld: DialogueWorldAdapter { get }
    var hud: HUDCoordinator { get }
    var inventory: InventoryCoordinator { get }
    var localizedStringsLoader: (() -> LocalizedStrings)? { get }
    var magic: MagicCoordinator { get }
    var mapWorld: MapWorldAdapter { get }
    var menuWorld: MenuWorldAdapter { get }
    var perks: PerkCoordinator { get }
    var runtimeState: RuntimeStateCoordinator { get }
    var streamer: CellStreamer? { get }
    var worldData: WorldDataStores? { get }
    var worldState: WorldStateStore { get }
    var journalMenu: JournalMenuController { get }
    var scripts: ScriptCoordinator { get }
}

/// Answers `PerkWorld` and `ProgressionWorld` from the session systems `game` owns.
final class ProgressionWorldAdapter {
    unowned let game: any ProgressionWorldHost

    init(game: any ProgressionWorldHost) {
        self.game = game
    }

    /// The caster takes the runtime when its cast loop is built. The live
    /// conditions carry the globals, so no snapshot of them is kept.
    func perkRuntime() -> PerkRuntime? {
        guard let store = game.worldData?.perkStore else { return nil }
        var runtime = PerkRuntime(
            store: game.worldState, perks: store, conditionRegistry: .standard
        )
        runtime.liveConditions = { [weak game] references in
            game?.runtimeState.conditionContext(indexing: references) ?? ConditionContext()
        }
        return runtime
    }

    /// Every skill write goes through the actor-value runtime.
    func progressionData() -> ProgressionSessionData? {
        game.worldData.flatMap { provider in
            game.actorValues.runtime.map { values in
                ProgressionSessionData(
                    values: values,
                    information: provider.actorValueInformation,
                    perkStore: provider.perkStore,
                    skillSettings: provider.skillAdvancementSettings,
                    levelSettings: provider.characterLevelSettings,
                    training: TrainingSettings
                        .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) },
                    texts: ProgressionTexts
                        .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
                )
            }
        }
    }

    private func inventoryHolder(of key: ReferenceKey) -> InventoryHolder? {
        key == .player ? .player : game.streamer?.inventoryHolder(of: key)
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

    func perksFromActiveEffects(on holder: ActorValueHolder) -> Set<ReferenceKey> {
        guard
            let effects = game.magic.effects,
            let perks = game.perks.runtime?.perks
        else { return [] }
        return ActiveEffectPerks.perks(
            of: effects.active(on: holder), effects: effects.effects, perks: perks
        )
    }

    /// Through the script bridge, as `SetStage` does, so the stage fragment runs. A
    /// quest of another plugin than the quest store's is not resolved.
    func setPerkQuestStage(_ stage: UInt16, quest: FormID, fromPlugin plugin: String) {
        guard
            let quests = game.journalMenu.questRuntime,
            plugin
                .caseInsensitiveCompare(game.worldData?.magicItemPluginName ?? "") == .orderedSame,
            let key = quests.quests.key(for: quest)
        else { return }
        if let bridge = game.scripts.bridge {
            _ = try? bridge.setQuestStage(stage, for: key)
        } else {
            _ = try? quests.setStage(stage, on: quest)
        }
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
            let parts = Self.armouredParts(of: item, in: items)
            switch items.armorType(item) {
            case .heavy: heavy += parts
            case .light: light += parts
            case .clothing, nil: continue
            }
        }
        return WornArmorProfile(heavyParts: heavy, lightParts: light)
    }

    /// The body slots `item` covers for the armour roll: a shield and a piece worth
    /// nothing count none, and the torso counts twice.
    static func armouredParts(of item: FormID, in items: ItemDefinitionStore) -> Int {
        guard
            let slots = items.armor[item.rawValue]?.bodyTemplate?.slots,
            !slots.contains(.shield),
            (items.definition(item)?.value ?? 0) > 0
        else { return 0 }
        return slots.rawValue.nonzeroBitCount + (slots.contains(.body) ? 1 : 0)
    }

    func conditionContext() -> ConditionContext {
        game.runtimeState.conditionContext()
    }

    func conditionText(_ condition: Condition) -> String {
        RuntimeStateConditionRunner.describe(condition, registry: .standard)
    }

    func playerIdentity() -> (name: String, race: String) {
        game.menuWorld.playerNameAndRace
    }

    func localizedStrings() -> LocalizedStrings? {
        game.localizedStringsLoader?()
    }
}
