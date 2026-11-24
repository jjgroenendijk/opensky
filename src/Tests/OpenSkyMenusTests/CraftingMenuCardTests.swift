// The crafting menu fills the item card, the line under it, the station's description,
// and the skill bar in the movie's own clips.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyInventoryInterface
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

@MainActor
struct CraftingMenuCardTests {
    private struct Movie {
        let runtime: SWFMovieRuntime
        let menuCalls: MenuMovieCallLog
        let cardCalls: MenuMovieCallLog
        let barCalls: MenuMovieCallLog
        let line: SWFDisplayObject
        let description: SWFDisplayObject
    }

    @discardableResult
    private static func node(
        _ name: String, in parent: SWFDisplayObject, text: Bool = false
    ) -> SWFDisplayObject {
        let child = SWFDisplayObject(content: text ? .editText(1) : .clip(nil))
        child.name = name
        parent.addChild(child, atDepth: UInt16(parent.children.count + 1))
        return child
    }

    private static func movie() throws -> Movie {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let menu = node("Menu", in: runtime.root)
        let holder = node("ItemInfoHolder", in: menu)
        let card = node("ItemInfo", in: holder)
        let line = node(
            "AdditionalDescription", in: node("AdditionalDescriptionHolder", in: holder),
            text: true
        )
        let description = node(
            "MenuDescription", in: node("MenuDescriptionHolder", in: menu), text: true
        )
        let bar = node("BottomBarInfo", in: menu)
        return Movie(
            runtime: runtime,
            menuCalls: MenuMovieCallLog(runtime: runtime, names: ["FadeInfoCard"], on: menu),
            cardCalls: MenuMovieCallLog(runtime: runtime, names: ["__set__itemInfo"], on: card),
            barCalls: MenuMovieCallLog(runtime: runtime, names: ["UpdateCraftingInfo"], on: bar),
            line: line,
            description: description
        )
    }

    private static func forge() -> (FakeMenuScreenWorld, CraftingMenuCoordinator) {
        let world = FakeMenuScreenWorld()
        world.craftingStationName = "Forge"
        var recipe = CraftingMenuRecipe(
            id: ResolvedFormID(plugin: "Skyrim.esm", objectID: 1), name: "Iron Dagger",
            canMake: true
        )
        recipe.created = FormID(0x1397E)
        recipe.requirements = "Iron Ingot (3/1)"
        world.craftingRecipes = [recipe]
        world.itemCards[FormID(0x1397E)] = InventoryItemCard(
            layout: .weapon, name: "Iron Dagger", kind: "Dagger", value: 10, weight: 2
        )
        world.craftingDescription = "Create"
        world.craftingSkill = CraftingSkillBar(name: "Smithing", level: 15, progress: 0.25)
        return (world, CraftingMenuCoordinator(menuMode: MenuModeController(), world: world))
    }

    @Test func theSelectedRecipeShowsTheItemItMakesAndItsComponents() throws {
        let (world, menu) = Self.forge()
        #expect(menu.open())
        let movie = try Self.movie()

        menu.publishMovie(movie.runtime)

        #expect(movie.cardCalls.arguments(of: "__set__itemInfo")?.count == 1)
        #expect(movie.menuCalls.arguments(of: "FadeInfoCard") == [.boolean(true)])
        #expect(movie.line.textOverride == "Iron Ingot (3/1)")
        let hidden = movie.runtime.node(atPath: "/Menu", from: movie.runtime.root)?
            .object.ownProperty("bHideAdditionalDescription")?.value
        #expect(hidden == .boolean(false))
        withExtendedLifetime(world) {}
    }

    @Test func aRowWithNoItemFadesTheCardOut() throws {
        let movie = try Self.movie()
        CraftingMenuMovieBridge.publishCard(nil, line: nil, runtime: movie.runtime)
        #expect(movie.cardCalls.calls.isEmpty)
        #expect(movie.menuCalls.arguments(of: "FadeInfoCard") == [.boolean(false)])
        #expect(movie.line.textOverride?.isEmpty == true)
    }

    @Test func theHeaderShowsTheDescriptionAndTheSkillBar() throws {
        let (world, menu) = Self.forge()
        #expect(menu.open())
        let movie = try Self.movie()

        menu.activateMovie(movie.runtime)

        #expect(movie.description.textOverride == "Create")
        #expect(menu.skillBar == "Smithing 15, 25%")
        #expect(menu.readout.title == "Crafting: Can make")
        #expect(menu.movieState.error == "No game data located.")
        #expect(movie.barCalls.arguments(of: "UpdateCraftingInfo") == [
            .string("Smithing"), .integer(15), .number(25)
        ])
        withExtendedLifetime(world) {}
    }

    @Test func aStationWithoutASkillLeavesTheBottomBar() throws {
        let movie = try Self.movie()
        CraftingMenuMovieBridge.publishHeader(description: "", skill: nil, runtime: movie.runtime)
        #expect(movie.barCalls.calls.isEmpty)
    }
}
