import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

@MainActor
struct CraftingMenuEnchantingTests {
    private func world() -> FakeMenuScreenWorld {
        let world = FakeMenuScreenWorld()
        world.craftingStationName = "Enchanting: Choose"
        var choices = EnchanterChoices()
        choices.disenchantable = [EnchanterItem(id: FormID(1), name: "Ring of Fire")]
        choices.enchantable = [EnchanterItem(id: FormID(2), name: "Iron Sword")]
        choices.enchantments = [
            EnchanterBase(key: .plugin(name: "Skyrim.esm", objectID: 3), name: "Fire Damage")
        ]
        choices.gems = [EnchanterGem(item: FormID(4), soul: 5, name: "Soul Gem (Grand)")]
        world.enchanterChoices = choices
        return world
    }

    @Test func theEnchanterListsItsFourTabsInTheGamesOrder() {
        let world = world()
        let menu = CraftingMenuCoordinator(menuMode: MenuModeController(), world: world)
        menu.open()
        #expect(menu.panel.title.hasSuffix("Disenchant"))
        #expect(menu.panel.lines.count == 1)
    }

    @Test func destroyingAnItemAsksFirstAndThenShowsTheLesson() throws {
        let world = world()
        var enchanting = CraftingMenuEnchanting()
        let tabs = try enchanting.categories(
            #require(world.enchanterChoices),
            texts: world.enchantingTexts
        )
        _ = enchanting.choose(tabs[0].rows[0], alternate: false, world: world) {}
        #expect(world.questions.map(\.text) == [EnchantingMenuText.confirmDisenchant.fallback])
        world.questions[0].answer(true)
        #expect(world.actions == ["disenchant 1"])
        #expect(world.boxes == ["Learned"])
    }

    @Test func makingNeedsEveryPartAndAsksBeforeItEnchants() throws {
        let world = world()
        var enchanting = CraftingMenuEnchanting()
        let tabs = try enchanting.categories(
            #require(world.enchanterChoices),
            texts: world.enchantingTexts
        )
        world.enchantRefusalText = EnchantingMenuText.mustChoose.fallback
        _ = enchanting.choose(tabs[1].rows[0], alternate: true, world: world) {}
        #expect(world.hudLines == [EnchantingMenuText.mustChoose.fallback])
        world.enchantRefusalText = nil
        for tab in tabs.dropFirst() {
            _ = enchanting.choose(tab.rows[0], alternate: false, world: world) {}
        }
        #expect(enchanting.selection.isComplete)
        _ = enchanting.choose(tabs[1].rows[0], alternate: true, world: world) {}
        world.questions.last?.answer(true)
        #expect(world.actions == ["enchant 2 1"])
        #expect(!enchanting.selection.isComplete)
    }

    @Test func aKnownEnchantmentIsNotDestroyed() throws {
        let world = world()
        world.enchanterChoices?.disenchantable[0].isKnown = true
        var enchanting = CraftingMenuEnchanting()
        let tabs = try enchanting.categories(
            #require(world.enchanterChoices),
            texts: world.enchantingTexts
        )
        _ = enchanting.choose(tabs[0].rows[0], alternate: false, world: world) {}
        #expect(world.questions.isEmpty)
        #expect(world.hudLines == [EnchantingMenuText.alreadyKnown.fallback])
    }

    @Test func leavingWithAChoiceAsksFirst() {
        let world = world()
        let menu = CraftingMenuCoordinator(menuMode: MenuModeController(), world: world)
        menu.open()
        menu.route(.button(.cancel))
        #expect(!menu.isOpen)
        menu.open()
        menu.route(.move(.right))
        menu.route(.button(.accept))
        menu.route(.button(.cancel))
        #expect(world.questions.map(\.text) == [CraftingButtonText.quitEnchanting.fallback])
        #expect(menu.isOpen)
    }
}
