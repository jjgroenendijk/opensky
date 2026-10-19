// The menu a crafting station opens: its recipes, split into those the player can make
// now and the rest. At an alchemy lab it lists the carried ingredients instead, to
// choose and brew. The rules stay in the inventory feature.
// See docs/engine/crafting.md#crafting-menu.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyRendering

/// One recipe of the open station.
nonisolated public struct CraftingMenuRecipe: Equatable, Sendable {
    public let id: ResolvedFormID
    public let name: String
    public let canMake: Bool

    public init(id: ResolvedFormID, name: String, canMake: Bool) {
        self.id = id
        self.name = name
        self.canMake = canMake
    }
}

/// One carried ingredient at an alchemy lab.
nonisolated public struct CraftingMenuIngredient: Equatable, Sendable {
    public let id: FormID
    /// The name with the known effects, as the row shows it.
    public let name: String
    public let isChosen: Bool

    public init(id: FormID, name: String, isChosen: Bool) {
        self.id = id
        self.name = name
        self.isChosen = isChosen
    }
}

/// What the crafting menu needs from the app.
public protocol CraftingMenuWorld: MenuScreenWorld {
    /// The open station's name, or nil when no station is open.
    var craftingStationName: String? { get }
    var craftingRecipes: [CraftingMenuRecipe] { get }
    /// Makes one of `recipe`; the outcome text.
    func craft(_ recipe: ResolvedFormID) -> String
    func closeCraftingStation()
    /// The carried ingredients when the open station is an alchemy lab, else nil.
    var alchemyIngredients: [CraftingMenuIngredient]? { get }
    /// Chooses `ingredient`, or takes it out; the outcome text with the preview.
    func toggleIngredient(_ ingredient: FormID) -> String
    /// Brews the chosen ingredients; the outcome text.
    func brewChosenIngredients() -> String
}

public final class CraftingMenuCoordinator: ItemListMenuScreen {
    public static let identifier: MenuIdentifier = "Crafting Menu"
    public static let hint = "W/S: row   A/D: tab   E: make or choose   R: brew   Esc: leave"

    private var recipes: [ResolvedFormID] = []
    private var ingredients: [FormID] = []
    private weak var world: (any CraftingMenuWorld)?

    public init(
        menuMode: MenuModeController,
        movies: SWFMovieSource? = nil,
        hud: HUDCoordinator? = nil,
        world: (any CraftingMenuWorld)? = nil
    ) {
        self.world = world
        super.init(
            identifier: Self.identifier,
            movie: ItemListScreenMovie(
                path: CraftingMenuMovieBridge.moviePath, title: "Crafting", hint: Self.hint
            ),
            menuMode: menuMode, layer: (movies, hud), world: world
        )
    }

    override var layout: ItemListMovieLayout {
        CraftingMenuMovieBridge.layout
    }

    /// Opens the menu on the station the world has open.
    @discardableResult
    public func open() -> Bool {
        guard !isOpen else { return false }
        guard let station = world?.craftingStationName else {
            lastResult = "Not opened: no station open"
            return false
        }
        lastResult = "Open: \(station)"
        presentList()
        return true
    }

    override func loadCategories() -> [ItemListCategory] {
        if let carried = world?.alchemyIngredients {
            return ingredientCategories(carried)
        }
        ingredients = []
        let all = world?.craftingRecipes ?? []
        recipes = all.map(\.id)
        let rows = all.enumerated().map { index, recipe in
            ItemListRow(tag: UInt32(index), name: recipe.name, isEquipped: recipe.canMake)
        }
        return [
            ItemListCategory(label: "Can make", rows: rows.filter(\.isEquipped)),
            ItemListCategory(label: "All", rows: rows)
        ]
    }

    /// A chosen ingredient shows as equipped, as the vanilla lab marks it.
    private func ingredientCategories(_ carried: [CraftingMenuIngredient]) -> [ItemListCategory] {
        recipes = []
        ingredients = carried.map(\.id)
        let rows = carried.enumerated().map { index, ingredient in
            ItemListRow(tag: UInt32(index), name: ingredient.name, isEquipped: ingredient.isChosen)
        }
        return [
            ItemListCategory(label: "Ingredients", rows: rows),
            ItemListCategory(label: "Chosen", rows: rows.filter(\.isEquipped))
        ]
    }

    override func choose(_ row: ItemListRow, alternate: Bool) -> String {
        if !ingredients.isEmpty || world?.alchemyIngredients != nil {
            if alternate {
                return world?.brewChosenIngredients() ?? "No game"
            }
            guard ingredients.indices.contains(Int(row.tag)) else { return "No ingredient" }
            return world?.toggleIngredient(ingredients[Int(row.tag)]) ?? "No game"
        }
        guard recipes.indices.contains(Int(row.tag)) else { return "No recipe" }
        return world?.craft(recipes[Int(row.tag)]) ?? "No game"
    }

    override func prepareMovie(
        _ runtime: SWFMovieRuntime,
        post: @escaping @MainActor @Sendable (ItemListMovieEvent) -> Void
    ) {
        CraftingMenuMovieBridge.prepare(runtime: runtime, onEvent: post)
    }

    override func activateMovie(_ runtime: SWFMovieRuntime) {
        let station = world?.craftingStationName ?? ""
        CraftingMenuMovieBridge.activate(station: station, runtime: runtime)
    }

    override func didClose() {
        recipes = []
        ingredients = []
        world?.closeCraftingStation()
    }
}
