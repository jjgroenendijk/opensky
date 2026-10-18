// The small menu screens with their text panels: training, books, help, the spell and
// gift lists, and crafting. Each test drives keys and checks what the world was asked.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyMenus
import OpenSkyWorldInterface
import Testing

@MainActor
struct MenuScreenCoordinatorTests {
    private static let trainer = ReferenceKey(
        resolved: ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x13BB9)
    )

    private static func card(level: Int) -> TrainingCard {
        TrainingCard(
            skill: ("One-handed", level), progress: 0.5, trainer: ("Amren", 50),
            sessions: (0, 5), price: (250, 1000)
        )
    }

    @Test func trainingTrainsOnAcceptAndShowsARefusal() {
        let world = FakeMenuScreenWorld()
        world.cards[Self.trainer] = Self.card(level: 20)
        let menu = TrainingMenuCoordinator(menuMode: MenuModeController(), world: world)
        #expect(menu.open(trainer: Self.trainer))
        menu.route(.button(.accept))
        #expect(menu.card?.skillLevel == 21)
        #expect(menu.lastResult == "Trained to 21")
        world.trainRefusal = "You cannot train higher."
        menu.route(.button(.accept))
        #expect(menu.lastResult == "Refused: You cannot train higher.")
        #expect(menu.isOpen)
        menu.route(.button(.cancel))
        #expect(!menu.isOpen)
    }

    @Test func trainingStaysShutForAnActorThatDoesNotTrain() {
        let world = FakeMenuScreenWorld()
        let menu = TrainingMenuCoordinator(menuMode: MenuModeController(), world: world)
        #expect(!menu.open(trainer: Self.trainer))
        #expect(!menu.openNearest())
        #expect(menu.lastResult == "Not opened: no trainer nearby")
    }

    @Test func aBookTeachesOnOpenAndCloses() {
        let world = FakeMenuScreenWorld()
        world.books[FormID(0x10)] = BookContent(title: "Notes", text: "<p>Hello</p>", isNote: true)
        world.bookNotice = "Your Alteration skill has increased."
        let menuMode = MenuModeController()
        let menu = BookMenuCoordinator(menuMode: menuMode, world: world)
        #expect(menu.openFirstCarried())
        #expect(world.actions == ["read 16"])
        #expect(world.hudLines == ["Your Alteration skill has increased."])
        #expect(menuMode.topMenu == BookMenuCoordinator.identifier)
        menu.route(.button(.cancel))
        #expect(menuMode.topMenu == nil)
        #expect(!menu.isBook(FormID(0x11)))
    }

    @Test func aBookReadWhereItLiesIsStolenOnAccept() {
        let world = FakeMenuScreenWorld()
        world.books[FormID(0x10)] = BookContent(title: "Notes", text: "Hello", isNote: false)
        let menu = BookMenuCoordinator(menuMode: MenuModeController(), world: world)
        var taken = 0
        let offer = BookTakeOffer(isTheft: true) { taken += 1 }
        #expect(menu.open(item: FormID(0x10), takeOffer: offer))
        #expect(menu.takeButton == .steal)
        menu.route(.button(.accept))
        #expect(taken == 1)
        #expect(menu.lastResult == "Stole: Notes")
        #expect(!menu.isOpen)
        #expect(menu.takeButton == .hidden)
    }

    @Test func helpOpensTheFirstTopic() {
        let world = FakeMenuScreenWorld()
        world.topics["HelpAlchemyLong"] = HelpTopic(
            editorID: "HelpAlchemyLong", title: "Alchemy", text: "Press [Activate]."
        )
        let menu = TutorialMenuCoordinator(menuMode: MenuModeController(), world: world)
        #expect(menu.openFirstTopic())
        #expect(menu.isOpen)
        #expect(HelpTopic.isTopic(editorID: "HelpAlchemyLong"))
        #expect(!HelpTopic.isTopic(editorID: "HelpAlchemyShort"))
    }

    @Test func magicReadiesTheSelectedSpellInEitherHand() {
        let world = FakeMenuScreenWorld()
        world.categories = [ItemListCategory(label: "All", rows: [
            ItemListRow(tag: 0, name: "Flames"), ItemListRow(tag: 1, name: "Healing")
        ])]
        let menu = MagicMenuCoordinator(menuMode: MenuModeController(), world: world)
        #expect(menu.open())
        menu.route(.move(.down))
        menu.route(.button(.accept))
        menu.route(.button(.xButton))
        #expect(world.actions == ["ready 1 right", "ready 1 left"])
        #expect(menu.lastResult == "Readied")
    }

    @Test func giftGivesTheSelectedItem() {
        let world = FakeMenuScreenWorld()
        world.nearestTrainer = Self.trainer
        world.categories = [ItemListCategory(label: "All", rows: [
            ItemListRow(tag: 0x12EB7, name: "Iron Dagger", count: 2)
        ])]
        let menu = GiftMenuCoordinator(menuMode: MenuModeController(), world: world)
        #expect(menu.openNearest())
        menu.route(.button(.accept))
        #expect(world.actions == ["give 77495 true"])
    }

    @Test func aGiftFilterKeepsMatchingHonestItems() {
        let food = ReferenceKey(resolved: ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x8CDEA))
        let bread = ReferenceKey(resolved: ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x65C9F))
        let request = GiftMenuRequest(giving: true, filter: [food])
        #expect(request.shows(stolen: false, identities: [bread, food]))
        #expect(!request.shows(stolen: true, identities: [bread, food]))
        #expect(!request.shows(stolen: false, identities: [bread]))
        #expect(GiftMenuRequest(giving: true).shows(stolen: false, identities: []))
    }

    @Test func craftingListsWhatCanBeMadeFirstAndClosesTheStation() {
        let world = FakeMenuScreenWorld()
        let menu = CraftingMenuCoordinator(menuMode: MenuModeController(), world: world)
        #expect(!menu.open())
        world.craftingStationName = "Forge"
        world.craftingRecipes = [
            CraftingMenuRecipe(
                id: ResolvedFormID(plugin: "Skyrim.esm", objectID: 1), name: "Steel Sword",
                canMake: false
            ),
            CraftingMenuRecipe(
                id: ResolvedFormID(plugin: "Skyrim.esm", objectID: 2), name: "Iron Dagger",
                canMake: true
            )
        ]
        #expect(menu.open())
        #expect(menu.model.categories.map(\.label) == ["Can make", "All"])
        #expect(menu.model.rows.map(\.name) == ["Iron Dagger"])
        menu.route(.button(.accept))
        #expect(world.actions == ["craft 2"])
        menu.route(.button(.cancel))
        #expect(world.actions.last == "close station")
    }
}
