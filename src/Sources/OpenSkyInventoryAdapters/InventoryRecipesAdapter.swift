import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `InventoryRecipesAdapter` reads from the session.
@MainActor
public protocol InventoryRecipesHost: AnyObject {
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var inventory: any InventoryPort { get }
    var perks: any PerkPort { get }
    var runtimeState: any RuntimeStatePort { get }
}

/// Part of `InventoryWorldAdapter`, over its own narrow host.
public struct InventoryRecipesAdapter {
    public let game: any InventoryRecipesHost
}

extension InventoryRecipesAdapter {
    /// Recipes run on the player, who also answers `GetItemCount`.
    public func failingFunction(
        in conditions: ConditionList,
        sourcePlugin _: String,
        temperingEnchanted: Bool?
    ) -> String? {
        var context = game.runtimeState.conditionContext()
        context.subject = .player
        context.tempering = TemperingConditionResolution(isEnchanted: temperingEnchanted)
        var evaluator = ConditionEvaluator(context: context)
        return evaluator.firstFailure(in: conditions.conditions).map(evaluator.functionName(of:))
    }

    public func skillLevel(at index: Int32) -> Float? {
        guard
            let runtime = game.actorValues.runtime,
            let holder = game.actorWorld.actorValueHolder(for: .player)
        else { return nil }
        return runtime.value(at: index, on: holder)
    }

    public func temperingFactor(for item: FormID) -> Float {
        let subject = game.inventory.itemDefinitions?.conditionSubject(of: item)
        let subjects = PerkEvaluationSubjects(owner: .player).binding(.item, to: subject)
        return game.perks.modified(
            1, at: .modTemperingHealth, on: .player, subjects: { _ in subjects },
            seams: ConditionContext()
        )
    }
}
