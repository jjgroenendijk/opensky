// A live crafting session at one station, run without UI like a container
// session. Verdicts are read fresh on every call. A craft consumes and creates in
// one inventory write, then reports a skill use. See docs/engine/crafting.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
import OpenSkyWorldInterface

/// Answers a recipe's conditions for the player.
@MainActor
public protocol RecipeConditionChecking: AnyObject {
    /// The name of the first failing condition function, or nil when the list passes.
    func failingFunction(in conditions: ConditionList, sourcePlugin: String) -> String?
}

nonisolated public enum CraftingError: Error, Equatable {
    case unknownRecipe(ResolvedFormID)
    case notEligible(ResolvedFormID, RecipeEligibility)
}

/// One recipe with its current verdict.
nonisolated public struct CraftingRecipeStatus: Equatable, Sendable {
    public let recipe: CraftingRecipe
    public let eligibility: RecipeEligibility
}

/// What one craft did.
nonisolated public struct CraftOutcome: Equatable, Sendable {
    public let consumed: [InventoryStack]
    public let created: InventoryStack
    /// Skill experience the progression runtime awarded. Zero without one.
    public let experience: Float
}

@MainActor
public final class CraftingSession {
    public let interaction: PlacedInteraction
    public let station: CraftingStationInfo
    public let recipes: [CraftingRecipe]

    private let inventory: InventoryRuntime
    private let player: InventoryHolder
    private weak var conditions: (any RecipeConditionChecking)?
    private weak var skills: (any SkillUseReporting)?

    public init(
        event: CraftingActivationEvent,
        catalog: CraftingCatalog,
        inventory: InventoryRuntime,
        player: InventoryHolder = .player,
        conditions: (any RecipeConditionChecking)?,
        skills: (any SkillUseReporting)?
    ) {
        interaction = event.interaction
        station = catalog.station(
            workbench: event.station.workbench, keywords: event.station.keywords
        )
        recipes = catalog.recipes(at: station)
        self.inventory = inventory
        self.player = player
        self.conditions = conditions
        self.skills = skills
    }

    /// Every offered recipe with its verdict right now.
    public var statuses: [CraftingRecipeStatus] {
        recipes.map { CraftingRecipeStatus(recipe: $0, eligibility: eligibility(of: $0)) }
    }

    public func eligibility(of recipe: CraftingRecipe) -> RecipeEligibility {
        let held = inventory.inventory(of: player)
        let items = inventory.baselines.items
        return CraftingCatalog.eligibility(
            of: recipe,
            held: { held.count(of: $0) },
            isKnownItem: { items.definition($0) != nil },
            failingFunction: conditions?.failingFunction(
                in: recipe.conditions, sourcePlugin: recipe.sourcePlugin
            )
        )
    }

    /// Makes `id` once. A failed precondition writes nothing.
    /// - Throws: `CraftingError`, or the inventory arithmetic errors.
    @discardableResult
    public func craft(_ id: ResolvedFormID) throws -> CraftOutcome {
        guard let recipe = recipes.first(where: { $0.id == id }) else {
            throw CraftingError.unknownRecipe(id)
        }
        let verdict = eligibility(of: recipe)
        guard verdict.isEligible, let item = recipe.created else {
            throw CraftingError.notEligible(id, verdict)
        }
        let consumed = CraftingCatalog.required(recipe).compactMap { component in
            component.item.map { InventoryStack(item: $0, count: component.count) }
        }
        let created = InventoryStack(item: item, count: recipe.createdCount)
        try inventory.apply(removing: consumed, adding: [created], on: player)
        return CraftOutcome(
            consumed: consumed,
            created: created,
            experience: reportSkillUse(created)
        )
    }

    private func reportSkillUse(_ created: InventoryStack) -> Float {
        guard let skill = station.skill, let skills else { return 0 }
        let value = inventory.baselines.items.definition(created.item)?.value ?? 0
        return skills.reportSkillUse(SkillUseEvent(
            actor: player.key,
            action: .craft(skill: skill),
            amount: Float(value) * Float(created.count)
        ))
    }
}
