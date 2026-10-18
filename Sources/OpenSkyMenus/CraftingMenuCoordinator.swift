// The menu a crafting station opens: its recipes, split into those the player can make
// now and the rest. The crafting rules stay in the inventory's crafting session.
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

/// What the crafting menu needs from the app.
public protocol CraftingMenuWorld: MenuScreenWorld {
    /// The open station's name, or nil when no station is open.
    var craftingStationName: String? { get }
    var craftingRecipes: [CraftingMenuRecipe] { get }
    /// Makes one of `recipe`; the outcome text.
    func craft(_ recipe: ResolvedFormID) -> String
    func closeCraftingStation()
}

public final class CraftingMenuCoordinator: ItemListMenuScreen {
    public static let identifier: MenuIdentifier = "Crafting Menu"
    public static let hint = "W/S: recipe   A/D: tab   E: make   Esc: leave"

    private var recipes: [ResolvedFormID] = []
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

    override func choose(_ row: ItemListRow, alternate _: Bool) -> String {
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
        world?.closeCraftingStation()
    }
}
