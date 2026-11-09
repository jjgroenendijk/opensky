// App side of `PerkCoordinator` and `ProgressionCoordinator`: builds their
// runtimes from the provider and answers both ports from the session systems.
// The rules live in the coordinators (docs/engine/coordinators.md).

import Foundation
public import OpenSkyCells
public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPlayer
public import OpenSkyProgression
public import OpenSkyProgressionInterface
import OpenSkyRuntimeState
public import OpenSkySessionInterface
import OpenSkyWorldConditions
import OpenSkyWorldInterface
public import OpenSkyWorldState

/// What `ProgressionWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol ProgressionWorldHost: AnyObject {
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var inventory: any InventoryPort { get }
    var localizedStringsLoader: (() -> LocalizedStrings)? { get }
    var mapWorld: any MapWorldPort { get }
    var menuWorld: any MenuWorldPort { get }
    var runtimeState: any RuntimeStatePort { get }
    var streamer: any CellStreamerPort { get }
    var worldData: WorldDataStores? { get }
}

/// Answers `PerkWorld` and `ProgressionWorld` from the session systems `game` owns.
public final class ProgressionWorldAdapter {
    public let game: any ProgressionWorldHost

    public let trainingHost: any ProgressionTrainingHost
    public let effectsHost: any ProgressionEffectsHost

    public var training: ProgressionTrainingAdapter {
        ProgressionTrainingAdapter(game: trainingHost
        )
    }

    public var effects: ProgressionEffectsAdapter {
        ProgressionEffectsAdapter(game: effectsHost
        )
    }

    public init(game: some ProgressionWorldHost & ProgressionTrainingHost &
        ProgressionEffectsHost)
    {
        trainingHost = game
        effectsHost = game
        self.game = game
    }

    /// The caster takes the runtime when its cast loop is built. The live
    /// conditions carry the globals, so no snapshot of them is kept.
    public func perkRuntime(store worldState: WorldStateStore) -> PerkRuntime? {
        guard let store = game.worldData?.perkStore else { return nil }
        var runtime = PerkRuntime(
            store: worldState, perks: store, conditionRegistry: .standard
        )
        runtime.liveConditions = { [weak game] references in
            game?.runtimeState.conditionContext(indexing: references) ?? ConditionContext()
        }
        return runtime
    }

    /// Every skill write goes through the actor-value runtime.
    public func progressionData() -> ProgressionSessionData? {
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
        key == .player ? .player : game.streamer.inventoryHolder(of: key)
    }
}

extension ProgressionWorldAdapter: PerkWorld {
    public func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        game.actorWorld.actorValueHolder(for: key)
    }

    public func actorValue(at index: Int32, on holder: ActorValueHolder) -> Float? {
        game.actorValues.runtime?.value(at: index, on: holder)
    }
}

extension ProgressionWorldAdapter: ProgressionWorld {
    /// Only equipped armor counts; clothing trains neither armor skill. The
    /// item index is the melee runtime's, to avoid a second decode.
    public func wornArmor(of key: ReferenceKey) -> WornArmorProfile {
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
    public static func armouredParts(of item: FormID, in items: ItemDefinitionStore) -> Int {
        guard
            let slots = items.armor[item.rawValue]?.bodyTemplate?.slots,
            !slots.contains(.shield),
            (items.definition(item)?.value ?? 0) > 0
        else { return 0 }
        return slots.rawValue.nonzeroBitCount + (slots.contains(.body) ? 1 : 0)
    }

    public func conditionContext() -> ConditionContext {
        game.runtimeState.conditionContext()
    }

    public func conditionText(_ condition: Condition) -> String {
        RuntimeStateConditionRunner.describe(condition, registry: .standard)
    }

    public func playerIdentity() -> (name: String, race: String) {
        game.menuWorld.playerNameAndRace
    }

    public func localizedStrings() -> LocalizedStrings? {
        game.localizedStringsLoader?()
    }
}

extension ProgressionWorldAdapter: ProgressionWorldPort {}
