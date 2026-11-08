import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
public import OpenSkyMenus
import OpenSkyScripting
public import OpenSkySessionInterface

/// What `MenuScreensCraftingDeskAdapter` reads from the session.
@MainActor
public protocol MenuScreensCraftingDeskHost: AnyObject {
    var inventory: any InventoryPort { get }
    var magic: any MagicPort { get }
    var mapWorld: any MapWorldPort { get }
    var scripts: any ScriptPort { get }
}

/// Part of `MenuScreensWorldAdapter`, over its own narrow host.
public struct MenuScreensCraftingDeskAdapter {
    public unowned let game: any MenuScreensCraftingDeskHost
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
        game.magic.readBook(item)?.text
    }

    public func noteBookRead(_ item: FormID, reference: FormID?) {
        guard let bridge = game.scripts.bridge else { return }
        if let reference, let key = bridge.referenceKey(forFormID: reference) {
            game.scripts.runtime?.queueRead(on: key)
        } else if let base = bridge.referenceKey(forFormID: item) {
            bridge.queueItemScriptEvent(PapyrusEngineEvents.onRead, base: base, arguments: [])
        }
    }

    public var carriedBooks: [FormID] {
        guard let runtime = game.inventory.runtime, let items else { return [] }
        return runtime.inventory.inventory(of: .player).stacks
            .map(\.item)
            .filter { items.books[$0.rawValue] != nil }
            .sorted { $0.rawValue < $1.rawValue }
    }
}

extension MenuScreensCraftingDeskAdapter {
    public var craftingStationName: String? {
        game.inventory.craftingSnapshot.stationName
    }

    public var craftingRecipes: [CraftingMenuRecipe] {
        game.inventory.craftingSnapshot.recipes.filter(\.isOffered).map {
            CraftingMenuRecipe(id: $0.id, name: $0.name, canMake: $0.isEligible)
        }
    }

    public func craft(_ recipe: ResolvedFormID) -> String {
        game.inventory.craft(recipe).text(game.mapWorld.settingTexts())
    }

    public func closeCraftingStation() {
        game.inventory.closeCraftingSession()
    }

    public var alchemyIngredients: [CraftingMenuIngredient]? {
        guard game.inventory.alchemySelection != nil else { return nil }
        return game.inventory.alchemyIngredients.map {
            CraftingMenuIngredient(
                id: $0.id,
                name: "\($0.name) (\($0.count)): \($0.effectsText)",
                isChosen: $0.isChosen
            )
        }
    }

    public func toggleIngredient(_ ingredient: FormID) -> String {
        game.inventory.toggleAlchemyIngredient(ingredient).text
    }

    public func brewChosenIngredients() -> String {
        game.inventory.brewChosenIngredients().text
    }
}
