// One fake world behind every small menu screen, so each test sets only the answers
// its screen reads.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyMenus
import OpenSkyRenderCore
import OpenSkyRendering

@MainActor
final class FakeMenuScreenWorld: MenuScreenWorld, MenuInputConsumer {
    var renderer: Renderer? {
        nil
    }

    var viewCamera: FreeFlyCamera? {
        nil
    }

    var uiScene = UIScene.empty
    var hudLines: [String] = []
    var actions: [String] = []

    var cards: [ReferenceKey: TrainingCard] = [:]
    var trainRefusal: String?
    var nearestTrainer: ReferenceKey?

    var books: [FormID: BookContent] = [:]
    var bookNotice: String?

    var topics: [String: HelpTopic] = [:]

    var categories: [ItemListCategory] = []

    var craftingStationName: String?
    var craftingRecipes: [CraftingMenuRecipe] = []
    var alchemyIngredients: [CraftingMenuIngredient]?

    func showHUDNotification(_ text: String) {
        hudLines.append(text)
    }

    var menuInputConsumer: (any MenuInputConsumer)? {
        self
    }

    func handleMenuInput(_ event: MenuInputEvent) {}
}

extension FakeMenuScreenWorld: TrainingMenuWorld {
    func trainingCard(trainer: ReferenceKey) -> TrainingCard? {
        cards[trainer]
    }

    func train(with trainer: ReferenceKey) -> String? {
        actions.append("train \(trainer)")
        guard trainRefusal == nil, var card = cards[trainer] else { return trainRefusal }
        card.skillLevel += 1
        cards[trainer] = card
        return nil
    }
}

extension FakeMenuScreenWorld: BookMenuWorld {
    func bookContent(_ item: FormID) -> BookContent? {
        books[item]
    }

    func readBook(_ item: FormID) -> String? {
        actions.append("read \(item.rawValue)")
        return bookNotice
    }

    var carriedBooks: [FormID] {
        books.keys.sorted { $0.rawValue < $1.rawValue }
    }
}

extension FakeMenuScreenWorld: TutorialMenuWorld {
    func helpTopic(_ editorID: String) -> HelpTopic? {
        topics[editorID]
    }

    var helpTopicEditorIDs: [String] {
        topics.keys.sorted()
    }

    func buttonName(forUserEvent event: String) -> String? {
        event == "Activate" ? "E" : nil
    }
}

extension FakeMenuScreenWorld: MagicMenuWorld, GiftMenuWorld, CraftingMenuWorld {
    var magicMenuCategories: [ItemListCategory] {
        categories
    }

    func readySpell(at index: Int, leftHand: Bool) -> String {
        actions.append("ready \(index) \(leftHand ? "left" : "right")")
        return "Readied"
    }

    func giftCategories(actor: ReferenceKey, request: GiftMenuRequest) -> [ItemListCategory] {
        categories
    }

    func give(_ item: FormID, actor: ReferenceKey, giving: Bool) -> String {
        actions.append("give \(item.rawValue) \(giving)")
        return "Gave"
    }

    var nearestActor: ReferenceKey? {
        nearestTrainer
    }

    func craft(_ recipe: ResolvedFormID) -> String {
        actions.append("craft \(recipe.objectID)")
        return "Crafted"
    }

    func closeCraftingStation() {
        actions.append("close station")
    }

    func toggleIngredient(_ ingredient: FormID) -> String {
        actions.append("toggle \(ingredient.rawValue)")
        return "Chose"
    }

    func brewChosenIngredients() -> String {
        actions.append("brew")
        return "Brewed"
    }
}
