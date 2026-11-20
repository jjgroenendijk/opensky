// The pause menu with the cursor: a click without the movie is accept, and a row the
// movie changed itself writes the player setting.

import Foundation
import OpenSkyFormatsSWF
@testable import OpenSkyGameData
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

struct SystemMenuPointerTests {
    @MainActor
    private static func makeMenu() -> (SystemMenuCoordinator, PlayerSettingsCoordinator) {
        let movies = SWFMovieSource()
        let settings = PlayerSettingsCoordinator(store: PlayerSettingsStore(persistence: nil))
        let menu = SystemMenuCoordinator(
            menuMode: MenuModeController(), movies: movies, hud: HUDCoordinator(movies: movies),
            settings: settings, saves: nil
        )
        return (menu, settings)
    }

    @Test @MainActor
    func aClickWithoutTheMovieIsAccept() {
        let (menu, _) = Self.makeMenu()
        menu.open()
        menu.route(MenuPointerEvent(.pressed, location: .zero, viewSize: SIMD2(800, 600)))
        #expect(!menu.isOpen, "accept on Resume closes the menu")
    }

    @Test @MainActor
    func aRowTheMovieChangedWritesTheSetting() throws {
        let (menu, settings) = Self.makeMenu()
        menu.open()
        menu.model.select(.settings)
        menu.route(.button(.accept))
        menu.openSettingsCategory(.gameplay)
        let row = try #require(menu.settingsPage.rows.firstIndex(of: .invertLook))
        menu.changeSetting(row: row, to: 1)
        #expect(settings.store.bool(.invertLook))
        #expect(menu.settingsPage.selectedRow == .invertLook)
        menu.changeSetting(row: 999, to: 1)
    }

    @Test @MainActor
    func aCategoryRequestFillsTheMovieRows() throws {
        let (menu, _) = Self.makeMenu()
        let gameplay = menu.openSettingsCategory(.gameplay).map(\.definition.title)
        #expect(!gameplay.contains("$Use Kinect Commands"))
        let rows = menu.openSettingsCategory(.audio)
        let runtime = AS2Runtime()
        let master = runtime.makeObject()
        master.assign(.string("$Master"), for: "text")
        let unknown = runtime.makeObject()
        unknown.assign(.string("$Kinect"), for: "text")
        let list = runtime.makeArray([.object(master), .object(unknown)])
        SettingsMovieBridge.fill(list, with: rows, runtime: runtime)
        #expect(master.lookup("ID")?.property.value == .integer(0))
        #expect(master.lookup("value")?.property.value == .number(1))
        #expect(unknown.lookup("ID") == nil, "the movie drops a row without an ID")
        #expect(list.arrayLength == 2 + rows.count - 1, "the category volumes are added")
        let added = try #require(list.element(at: 2).objectValue)
        #expect(added.lookup("movieType")?.property.value == .integer(0))
        #expect(added.lookup("ID")?.property.value == .integer(1))
    }

    @Test func anOptionChangeCarriesTheRowAndTheValue() {
        let change = SettingsMovieBridge.optionChange([.integer(3), .number(0.25)])
        #expect(change?.row == 3)
        #expect(change?.value == 0.25)
        #expect(SettingsMovieBridge.optionChange([.number(1.5), .integer(1)]) == nil)
        #expect(SettingsMovieBridge.optionChange([.integer(1)]) == nil)
    }
}
