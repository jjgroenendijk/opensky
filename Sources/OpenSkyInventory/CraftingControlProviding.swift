// Main-app crafting and harvest seam: the open station's recipes with their
// verdicts, the station list, and the crosshair plant. AppKit-free.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldInterface

/// One recipe row: what it makes and whether the player can make it now.
nonisolated public struct CraftingRecipeReadout: Equatable, Sendable {
    public let id: ResolvedFormID
    public let name: String
    public let isEligible: Bool
    /// False when a condition fails, so the crafting menu leaves the recipe out.
    public let isOffered: Bool

    public init(
        id: ResolvedFormID, name: String, isEligible: Bool, isOffered: Bool = true
    ) {
        self.id = id
        self.name = name
        self.isEligible = isEligible
        self.isOffered = isOffered
    }
}

nonisolated public struct CraftingControlSnapshot: Equatable, Sendable {
    public let stationName: String?
    public let recipes: [CraftingRecipeReadout]

    public static let unavailable = CraftingControlSnapshot(
        stationName: nil,
        recipes: []
    )

    public init(
        stationName: String?,
        recipes: [CraftingRecipeReadout]
    ) {
        self.stationName = stationName
        self.recipes = recipes
    }
}

extension InventoryCoordinator {
    public var craftingSnapshot: CraftingControlSnapshot {
        guard runtime != nil else { return .unavailable }
        return CraftingControlSnapshot(
            stationName: crafting?.interaction.name,
            recipes: crafting?.statuses.map(recipeReadout) ?? []
        )
    }

    private func recipeReadout(_ status: CraftingRecipeStatus) -> CraftingRecipeReadout {
        let recipe = status.recipe
        let itemName = recipe.created.map(name(of:)) ?? recipe.editorID ?? recipe.id.description
        guard let temper = status.temper else {
            return CraftingRecipeReadout(
                id: recipe.id,
                name: itemName,
                isEligible: status.isReady,
                isOffered: status.eligibility.isOffered
            )
        }
        let copies = temper.copies.map { qualityName($0, of: temper.item) }
            .joined(separator: ", ")
        return CraftingRecipeReadout(
            id: recipe.id,
            name: "\(itemName) (\(copies))",
            isEligible: status.isReady,
            isOffered: true
        )
    }

    /// The quality name of `level`, from the weapon or the armour list.
    func qualityName(_ level: Int32, of item: FormID) -> String {
        let isWeapon = runtime?.inventory.baselines.items.weapon(item) != nil
        return temperingTexts.name(level: level, isWeapon: isWeapon)
    }
}
