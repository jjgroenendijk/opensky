// The menu layer passes down a stack: a box over a menu gives the layer back to the menu.

import OpenSkyEngineTesting
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

@MainActor
private final class Holder: MenuLayerHolder {
    var reclaims = 0

    func reclaimLayer() {
        reclaims += 1
    }
}

@MainActor
struct HUDLayerStackTests {
    @Test func theMenuUnderABoxGetsTheLayerBack() {
        let hud = HUDCoordinator(movies: SWFMovieSource())
        let menu = Holder()
        let box = Holder()
        hud.takeLayer(for: menu)
        hud.takeLayer(for: box)
        hud.release(by: box)
        #expect(menu.reclaims == 1)
        #expect(box.reclaims == 0)
        hud.release(by: menu)
        #expect(hud.layerHolders.isEmpty, "the menu layer empties")
    }

    @Test func aMenuClosingUnderABoxLeavesTheBoxOnScreen() {
        let hud = HUDCoordinator(movies: SWFMovieSource())
        let menu = Holder()
        let box = Holder()
        hud.takeLayer(for: menu)
        hud.takeLayer(for: box)
        hud.release(by: menu)
        #expect(box.reclaims == 0)
        #expect(hud.layerHolders.count == 1)
        hud.release(by: box)
        #expect(menu.reclaims == 0)
    }
}
