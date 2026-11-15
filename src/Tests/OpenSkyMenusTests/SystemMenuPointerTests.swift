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

    @Test func anOptionChangeCarriesTheRowAndTheValue() {
        let change = SettingsMovieBridge.optionChange([.integer(3), .number(0.25)])
        #expect(change?.row == 3)
        #expect(change?.value == 0.25)
        #expect(SettingsMovieBridge.optionChange([.number(1.5), .integer(1)]) == nil)
        #expect(SettingsMovieBridge.optionChange([.integer(1)]) == nil)
    }
}
