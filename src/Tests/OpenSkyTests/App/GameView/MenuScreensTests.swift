// A menu screen's routes keep it alive: the session stores two screens in their routes only.

@testable import OpenSky
import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

@MainActor
struct MenuScreensTests {
    @Test func aRouteOwnsItsScreen() {
        weak var released: CreationClubMenuCoordinator?
        let route = {
            let screen = CreationClubMenuCoordinator(menuMode: MenuModeController())
            released = screen
            return MenuScreens.route(screen)
        }()
        #expect(released != nil)
        route.tick(0)
        #expect(route.identifier == CreationClubMenuCoordinator.identifier)
    }
}
