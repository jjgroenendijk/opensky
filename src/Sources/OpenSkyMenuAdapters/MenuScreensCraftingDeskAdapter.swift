import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyProgressionInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface

/// What `MenuScreensCraftingDeskAdapter` reads from the session.
@MainActor
public protocol MenuScreensCraftingDeskHost: AnyObject, SendableMetatype {
    var inventory: any InventoryPort { get }
    var magic: any MagicPort { get }
    var mapWorld: any MapWorldPort { get }
    var messages: any MessageCoordinatorPort { get }
    var progression: any ProgressionPort { get }
    var scripts: any ScriptPort { get }
}

/// Part of `MenuScreensWorldAdapter`, over its own narrow host.
public struct MenuScreensCraftingDeskAdapter {
    public let game: any MenuScreensCraftingDeskHost
}

extension MenuScreensCraftingDeskAdapter {
    var items: ItemDefinitionStore? {
        game.inventory.runtime?.inventory.baselines.items
    }

    public func readBook(_ item: FormID) -> String? {
        game.magic.menuLines.readBookLine(item)
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

    var craftingStation: CraftingStationInfo? {
        game.inventory.craftingReadout.craftingSnapshot.station
    }

    var craftingDescription: String? {
        game.inventory.craftingReadout.craftingSnapshot.description
    }

    /// The bench's `WBDT` skill with the player's level and progress in it.
    var craftingSkill: CraftingSkillBar? {
        guard
            let index = craftingStation?.skill,
            let skill = game.progression.skillsMenuSkills.first(where: { $0.index == index })
        else { return nil }
        return CraftingSkillBar(
            name: skill.name, level: Int(skill.level), progress: skill.progress
        )
    }

    func craftingItemCard(_ item: FormID) -> InventoryItemCard? {
        game.inventory.itemCards.itemCard(for: item)
    }

    var craftingButtonTexts: GameSettingTexts<CraftingButtonText> {
        game.mapWorld.settingTexts()
    }

    var craftingTabTexts: GameSettingTexts<CraftingTabText> {
        game.mapWorld.settingTexts()
    }

    var craftingRecipes: [CraftingMenuRecipe] {
        let titles: GameSettingTexts<CraftingCategoryText> = game.mapWorld.settingTexts()
        return game.inventory.craftingReadout.craftingSnapshot.recipes.filter(\.isOffered).map {
            var recipe = CraftingMenuRecipe(
                id: $0.id, name: $0.name, canMake: $0.isEligible,
                category: $0.category.map { titles[$0] }, categoryRank: $0.category?.rank ?? 0
            )
            recipe.created = $0.created
            recipe.requirements = $0.requirements
            return recipe
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

extension MenuScreensCraftingDeskAdapter {
    public func confirm(_ text: String, answer: @escaping (Bool) -> Void) {
        let words = game.mapWorld.settingTexts(MessageBoxText.self)
        game.messages.presentChoices(
            title: nil, text: text, buttons: [words[.yes], words[.no]]
        ) { answer($0 == 0) }
    }

    public func inform(_ text: String) {
        let words = game.mapWorld.settingTexts(MessageBoxText.self)
        game.messages.presentChoices(title: nil, text: text, buttons: [words[.ok]]) { _ in }
    }
}

/// A book's text, and the script event of reading it.
@MainActor
struct MenuBookReads {
    let game: any MenuScreensCraftingDeskHost
    let items: ItemDefinitionStore?

    func bookContent(_ item: FormID) -> BookContent? {
        guard let book = items?.books[item.rawValue] else { return nil }
        return BookContent(
            title: game.inventory.name(of: item),
            text: game.mapWorld.text(book.text, kind: .dlstrings) ?? "",
            isNote: book.kind == .note,
            canBeTaken: !book.flags.contains(.cannotBeTaken)
        )
    }

    func noteBookRead(_ item: FormID, reference: FormID?) {
        guard let bridge = game.scripts.bridge else { return }
        if let reference, let key = bridge.referenceKey(forFormID: reference) {
            game.scripts.runtime?.queueRead(on: key)
        } else if let base = bridge.referenceKey(forFormID: item) {
            bridge.queueItemRead(base: base)
        }
    }
}
