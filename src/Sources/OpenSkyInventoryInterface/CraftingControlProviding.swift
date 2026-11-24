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
    /// The item the recipe makes, for the menu's item card.
    public var created: FormID?
    /// Each component with the count carried and the count needed, such as
    /// "Iron Ingot (3/1)"; nil for a recipe with none.
    public var requirements: String?

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
    /// The menu's title, such as "Forge: Create".
    public let header: String?
    /// What the open station does; nil with none open.
    public var station: CraftingStationInfo?
    /// The line that says what the station is for, such as "Create".
    public var description: String?
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
        self.header = header ?? stationName
        self.recipes = recipes
    }
}
