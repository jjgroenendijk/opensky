import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData

/// One recipe row: what it makes and whether the player can make it now.
nonisolated public struct CraftingRecipeReadout: Equatable, Sendable {
    public let id: ResolvedFormID
    public let name: String
    public let isEligible: Bool
    /// False when a condition fails, so the crafting menu leaves the recipe out.
    public let isOffered: Bool
    /// The tab the created item goes under, or nil for none of its own.
    public let category: CraftingCategoryText?

    public init(
        id: ResolvedFormID, name: String, isEligible: Bool, isOffered: Bool = true,
        category: CraftingCategoryText? = nil
    ) {
        self.id = id
        self.name = name
        self.isEligible = isEligible
        self.isOffered = isOffered
        self.category = category
    }
}

nonisolated public struct CraftingControlSnapshot: Equatable, Sendable {
    public let stationName: String?
    /// The menu's title, such as "Forge: Create".
    public let header: String?
    public let recipes: [CraftingRecipeReadout]

    public static let unavailable = CraftingControlSnapshot(
        stationName: nil,
        recipes: []
    )

    public init(
        stationName: String?,
        header: String? = nil,
        recipes: [CraftingRecipeReadout]
    ) {
        self.stationName = stationName
        self.header = header ?? stationName
        self.recipes = recipes
    }
}
