// The inventory movie owns its focus: an arrow key goes to the movie, and the model
// takes the category or row the movie then selects. A synthetic `/Menu_mc` tree
// stands in for the movie; its lists hold only `iSelectedIndex`.

import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
@testable import OpenSkyGameData
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

@MainActor
struct InventoryMenuNavigationTests {
    private struct Movie {
        let runtime: SWFMovieRuntime
        let lists: SWFDisplayObject
        let categories: SWFDisplayObject
        let items: SWFDisplayObject
    }

    private static func clip(_ name: String, in parent: SWFDisplayObject) -> SWFDisplayObject {
        let child = SWFDisplayObject(content: .clip(nil))
        child.name = name
        parent.addChild(child, atDepth: UInt16(parent.children.count + 1))
        return child
    }

    private static func movie() throws -> Movie {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let lists = clip("InventoryLists_mc", in: clip("Menu_mc", in: runtime.root))
        return Movie(
            runtime: runtime, lists: lists,
            categories: clip("List_mc", in: clip("CategoriesListHolder", in: lists)),
            items: clip("List_mc", in: clip("ItemsListHolder", in: lists))
        )
    }

    private static func model() -> InventoryMenuModel {
        let entries = (1 ... 3).map {
            InventoryMenuEntry(
                item: FormID(UInt32($0)), name: "\($0)", count: 1, weight: 0, value: 0,
                isEquipped: false, family: .weapon
            )
        }
        return InventoryMenuModel(
            allEntries: entries,
            categories: InventoryMenuCategory.tabs(texts: .vanilla, favourites: true),
            carriedWeight: 0, gold: 0
        )
    }

    @Test func theItemKeysWaitForTheSecondPanel() throws {
        let movie = try Self.movie()
        movie.lists.object.assign(.integer(1), for: "iCurrentState")
        #expect(!InventoryMenuMovieBridge.showsItems(runtime: movie.runtime))
        movie.lists.object.assign(.integer(2), for: "iCurrentState")
        #expect(InventoryMenuMovieBridge.showsItems(runtime: movie.runtime))
    }

    @Test func aNewCategoryFromTheMovieResetsTheRow() throws {
        let movie = try Self.movie()
        var model = Self.model()
        model.selectCategory(1)
        model.select(2)
        movie.categories.object.assign(.integer(2), for: "iSelectedIndex")
        movie.items.object.assign(.integer(1), for: "iSelectedIndex")
        var sent: [MenuInputEvent] = []
        let moved = InventoryMenuMovieBridge
            .navigate(.down, model: &model, runtime: movie.runtime) {
                sent.append($0)
                return true
            }
        #expect(moved)
        #expect(sent == [.move(.down)])
        #expect(model.selectedCategoryIndex == 2)
        #expect(model.selectedIndex == 0)
    }

    @Test func theSameCategoryTakesTheMoviesRow() throws {
        let movie = try Self.movie()
        var model = Self.model()
        let category = model.selectedCategoryIndex
        movie.categories.object.assign(.integer(category), for: "iSelectedIndex")
        movie.items.object.assign(.integer(2), for: "iSelectedIndex")
        let bridge = InventoryMenuMovieBridge.self
        let moved = bridge.navigate(.down, model: &model, runtime: movie.runtime) { _ in true }
        #expect(moved)
        #expect(model.selectedCategoryIndex == category)
        #expect(model.selectedIndex == 2)
    }

    @Test func aDeclinedKeyChangesNothing() throws {
        let movie = try Self.movie()
        var model = Self.model()
        let category = model.selectedCategoryIndex
        movie.categories.object.assign(.integer(category + 1), for: "iSelectedIndex")
        let bridge = InventoryMenuMovieBridge.self
        let moved = bridge.navigate(.right, model: &model, runtime: movie.runtime) { _ in false }
        #expect(!moved)
        #expect(model.selectedCategoryIndex == category)
    }

    @Test func theEngineSelectionAlsoScrollsTheCentredCategoryList() throws {
        let movie = try Self.movie()
        let calls = MenuMovieCallLog(
            runtime: movie.runtime, names: ["__set__scrollPosition"], on: movie.categories
        )
        InventoryMenuMovieBridge.publish(Self.model(), runtime: movie.runtime)
        let category = Self.model().selectedCategoryIndex
        #expect(calls.arguments(of: "__set__scrollPosition") == [.integer(category)])
    }
}
