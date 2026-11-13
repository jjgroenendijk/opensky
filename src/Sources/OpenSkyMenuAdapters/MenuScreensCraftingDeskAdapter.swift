import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
public import OpenSkyMenus
import OpenSkyScriptingInterface
public import OpenSkySessionInterface

/// What `MenuScreensCraftingDeskAdapter` reads from the session.
@MainActor
public protocol MenuScreensCraftingDeskHost: AnyObject, SendableMetatype {
    var inventory: any InventoryPort { get }
    var magic: any MagicPort { get }
    var mapWorld: any MapWorldPort { get }
    var scripts: any ScriptPort { get }
}

/// Part of `MenuScreensWorldAdapter`, over its own narrow host.
public struct MenuScreensCraftingDeskAdapter {
    public let game: any MenuScreensCraftingDeskHost
}

extension MenuScreensCraftingDeskAdapter {
    private var items: ItemDefinitionStore? {
        game.inventory.runtime?.inventory.baselines.items
    }

    public func bookContent(_ item: FormID) -> BookContent? {
        guard let book = items?.books[item.rawValue] else { return nil }
        return BookContent(
            title: game.inventory.name(of: item),
            text: game.mapWorld.text(book.text, kind: .dlstrings) ?? "",
            isNote: book.kind == .note
        )
    }

    public func readBook(_ item: FormID) -> String? {
        game.magic.menuLines.readBookLine(item)
    }

    public func noteBookRead(_ item: FormID, reference: FormID?) {
        guard let bridge = game.scripts.bridge else { return }
        if let reference, let key = bridge.referenceKey(forFormID: reference) {
            game.scripts.runtime?.queueRead(on: key)
        } else if let base = bridge.referenceKey(forFormID: item) {
            bridge.queueItemRead(base: base)
        }
    }

    var carriedBooks: [FormID] {
        guard let runtime = game.inventory.runtime, let items else { return [] }
        return runtime.inventory.inventory(of: .player).stacks
            .map(\.item)
            .filter { items.books[$0.rawValue] != nil }
            .sorted { $0.rawValue < $1.rawValue }
    }
}

extension MenuScreensCraftingDeskAdapter {
    /// The menu's title, which also says a station is open.
    var craftingStationName: String? {
        game.inventory.craftingReadout.craftingSnapshot.header
    }

    var craftingRecipes: [CraftingMenuRecipe] {
        let titles: GameSettingTexts<CraftingCategoryText> = game.mapWorld.settingTexts()
        return game.inventory.craftingReadout.craftingSnapshot.recipes.filter(\.isOffered).map {
            CraftingMenuRecipe(
                id: $0.id, name: $0.name, canMake: $0.isEligible,
                category: $0.category.map { titles[$0] }, categoryRank: $0.category?.rank ?? 0
            )
        }
    }

    public func craft(_ recipe: ResolvedFormID) -> String {
        game.inventory.readoutLines.craftLine(recipe, texts: game.mapWorld.settingTexts())
    }

    public func closeCraftingStation() {
        game.inventory.craftingBench.closeCraftingSession()
    }

    var alchemyIngredients: [CraftingMenuIngredient]? {
        guard game.inventory.alchemySelection != nil else { return nil }
        return game.inventory.alchemyLab.alchemyIngredients.map {
            CraftingMenuIngredient(
                id: $0.id,
                name: "\($0.name) (\($0.count)): \($0.effectsText)",
                isChosen: $0.isChosen
            )
        }
    }

    public func toggleIngredient(_ ingredient: FormID) -> String {
        game.inventory.readoutLines.toggleAlchemyIngredientLine(ingredient)
    }

    public func brewChosenIngredients() -> String {
        game.inventory.readoutLines.brewChosenIngredientsLine()
    }
}
