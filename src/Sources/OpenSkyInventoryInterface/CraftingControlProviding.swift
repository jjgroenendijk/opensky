import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData

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
