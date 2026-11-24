import OpenSkyFormatsESM
import OpenSkyFormatsSWF
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
        #expect(enchanting.isDestroyRow(tabs[0].rows[0]))
        #expect(!enchanting.isDestroyRow(tabs[1].rows[0]))
        enchanting.rename("Blade")
        #expect(enchanting.selection.name == "Blade")
        enchanting.rename(String(repeating: "a", count: 40))
        #expect(enchanting.selection.name?.count == CraftingMenuEnchanting.nameLimit)
        enchanting.rename("")
        #expect(enchanting.selection.name?.count == CraftingMenuEnchanting.nameLimit)
        enchanting.rename("Blade", allowed: "Blade")
        enchanting.rename("Bläde", allowed: "Blade")
        #expect(enchanting.selection.name == "Blade", "a refused character keeps the name")
        enchanting.rename(nil)
        #expect(enchanting.selection.name == "Blade")
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

    @Test func leavingWithAChoiceAsksFirst() throws {
        let world = world()
        let menu = CraftingMenuCoordinator(menuMode: MenuModeController(), world: world)
        menu.open()
        #expect(menu.buttons.labels.count == 4)
        menu.route(.button(.cancel))
        #expect(!menu.isOpen)
        menu.open()
        try menu.publishMovie(MenuMovieCallLog.emptyRuntime())
        menu.route(.move(.right))
        menu.route(.button(.accept))
        menu.route(.button(.cancel))
        #expect(world.questions.map(\.text) == [CraftingButtonText.quitEnchanting.fallback])
        #expect(menu.isOpen)
    }

    /// Choosing a base opens the slider at its maximum; a move previews, a close keeps,
    /// and a cancel keeps the value from before.
    @Test func theSliderPreviewsKeepsAndCancels() throws {
        let world = world()
        world.enchantingSliderOffer = EnchanterSlider(maximum: 10, step: 1, value: 10)
        var enchanting = CraftingMenuEnchanting()
        let tabs = try enchanting.categories(
            #require(world.enchanterChoices),
            texts: world.enchantingTexts
        )
        #expect(enchanting.slide(to: 3, accepted: nil, enchanter: world.enchanter) == "No slider")
        _ = enchanting.choose(tabs[1].rows[0], alternate: false, world: world) {}
        #expect(enchanting.takeSliderRequest() == nil)
        _ = enchanting.choose(tabs[2].rows[0], alternate: false, world: world) {}
        #expect(enchanting.takeSliderRequest()?.value == 10)
        #expect(enchanting.takeSliderRequest() == nil)
        #expect(enchanting.slide(to: 4, accepted: nil, enchanter: world.enchanter)
            .hasPrefix("Magnitude 4 of 10"))
        #expect(enchanting.selection.magnitude == nil)
        _ = enchanting.slide(to: 6, accepted: true, enchanter: world.enchanter)
        #expect(enchanting.selection.magnitude == 6)
        #expect(enchanting.slide(to: 2, accepted: false, enchanter: world.enchanter)
            .hasPrefix("Magnitude 6"))
        #expect(enchanting.selection.magnitude == 6)
        world.enchantingSliderOffer = EnchanterSlider(maximum: 20, step: 1, value: 20)
        _ = enchanting.choose(tabs[3].rows[0], alternate: false, world: world) {}
        #expect(enchanting.selection.magnitude == nil, "a new maximum resets the value")
    }

    @Test func theMovieSliderReachesTheEnchanter() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let events = MenuMovieEventLog<ItemListMovieEvent>()
        CraftingMenuMovieBridge.prepare(runtime: runtime) { events.append($0) }
        runtime.callHost("CalculateCharge", arguments: [.number(4.4)])
        runtime.callHost("SliderClose", arguments: [.number(5), .boolean(false)])
        runtime.callHost("SliderClose", arguments: [.string("x")])
        #expect(events.events == [
            .sliderMoved(4), .sliderClosed(5, accepted: false), .sliderClosed(0, accepted: true)
        ])
        CraftingMenuMovieBridge.showSlider(
            EnchanterSlider(maximum: 10, step: 1, value: 10), runtime: runtime
        )
        let menu = CraftingMenuCoordinator(menuMode: MenuModeController(), world: world())
        menu.handle(.sliderMoved(3))
        #expect(menu.lastResult == "No slider")
        menu.handle(.sliderClosed(3, accepted: true))
        #expect(menu.lastResult == "No slider")
    }
}
