// A live crafting session at one station, run without UI like a container
// session. Verdicts are read fresh on every call. A craft consumes and creates in
// one inventory write, then reports a skill use. A tempering station improves a
// held copy instead (`CraftingSession+Tempering`). See docs/engine/crafting.md.

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
    /// `temperingEnchanted` says whether the item a tempering recipe improves is
    /// enchanted; nil outside tempering.
    func failingFunction(
        in conditions: ConditionList,
        sourcePlugin: String,
        temperingEnchanted: Bool?
    ) -> String?
    /// The player's level in the skill at this actor-value index. Nil when unknown.
    func skillLevel(at index: Int32) -> Float?
}

nonisolated public enum CraftingError: Error, Equatable {
    case unknownRecipe(ResolvedFormID)
    case notEligible(ResolvedFormID, RecipeEligibility)
    /// Every held copy is already at the best quality the skill reaches.
    case notImprovable(ResolvedFormID)
}

/// One recipe with its current verdict.
nonisolated public struct CraftingRecipeStatus: Equatable, Sendable {
    public let recipe: CraftingRecipe
    public let eligibility: RecipeEligibility
    /// The held copies a tempering recipe improves. Nil at a crafting station.
    public let temper: TemperTarget?

    public init(recipe: CraftingRecipe, eligibility: RecipeEligibility, temper: TemperTarget?) {
        self.recipe = recipe
        self.eligibility = eligibility
        self.temper = temper
    }

    public var isReady: Bool {
        eligibility.isEligible && (temper.map { $0.from != nil } ?? true)
    }
}

/// What one craft did.
nonisolated public struct CraftOutcome: Equatable, Sendable {
    public let consumed: [InventoryStack]
    /// The made stack, or the one improved copy at a tempering station.
    public let created: InventoryStack
    /// Skill experience the progression runtime awarded. Zero without one.
    public let experience: Float
    /// The quality levels before and after a temper. Nil for a craft.
    public let improved: TemperStep?
}

@MainActor
public final class CraftingSession {
    public let interaction: PlacedInteraction
    public let station: CraftingStationInfo
    public let recipes: [CraftingRecipe]

    let inventory: InventoryRuntime
    let player: InventoryHolder
    weak var conditions: (any RecipeConditionChecking)?
    weak var skills: (any SkillUseReporting)?

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
        guard !station.improves else { return temperStatuses }
        return recipes.map {
            CraftingRecipeStatus(recipe: $0, eligibility: eligibility(of: $0), temper: nil)
        }
    }

    public func eligibility(of recipe: CraftingRecipe) -> RecipeEligibility {
        eligibility(of: recipe, temperingEnchanted: nil)
    }

    func eligibility(of recipe: CraftingRecipe, temperingEnchanted: Bool?) -> RecipeEligibility {
        let held = inventory.inventory(of: player)
        let items = inventory.baselines.items
        return CraftingCatalog.eligibility(
            of: recipe,
            held: { held.count(of: $0) },
            isKnownItem: { items.definition($0) != nil },
            failingFunction: conditions?.failingFunction(
                in: recipe.conditions,
                sourcePlugin: recipe.sourcePlugin,
                temperingEnchanted: temperingEnchanted
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
        if station.improves {
            return try temper(recipe)
        }
        let verdict = eligibility(of: recipe)
        guard verdict.isEligible, let item = recipe.created else {
            throw CraftingError.notEligible(id, verdict)
        }
        let consumed = Self.consumed(by: recipe)
        let created = InventoryStack(item: item, count: recipe.createdCount)
        try inventory.apply(removing: consumed, adding: [created], on: player)
        let value = inventory.baselines.items.definition(item)?.value ?? 0
        return CraftOutcome(
            consumed: consumed,
            created: created,
            experience: reportSkillUse(amount: Float(value) * Float(created.count)),
            improved: nil
        )
    }

    static func consumed(by recipe: CraftingRecipe) -> [InventoryStack] {
        CraftingCatalog.required(recipe).compactMap { component in
            component.item.map { InventoryStack(item: $0, count: component.count) }
        }
    }

    func reportSkillUse(amount: Float) -> Float {
        guard let skill = station.skill, let skills else { return 0 }
        return skills.reportSkillUse(SkillUseEvent(
            actor: player.key,
            action: .craft(skill: skill),
            amount: amount
        ))
    }
}
