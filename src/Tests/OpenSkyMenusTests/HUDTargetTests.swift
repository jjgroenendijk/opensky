// The HUD keeps the crosshair's idle prompt, the target's stat, and the compass places
// until they change.

import OpenSkyFormatsSWF
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

@MainActor
struct HUDTargetTests {
    @Test func theIdlePromptAndTheTargetStatAreKept() {
        let hud = HUDCoordinator(movies: SWFMovieSource())
        hud.setIdlePrompt("Sit")
        #expect(hud.idlePrompt == "Sit")
        hud.setIdlePrompt(nil)
        #expect(hud.idlePrompt == nil)
        let stat = HUDItemStat(value: 7, label: "DAMAGE")
        hud.updateTargetStat(stat)
        #expect(hud.targetStat == stat)
    }

    @Test func compassPlacesAreKeptUntilTheyChange() {
        let hud = HUDCoordinator(movies: SWFMovieSource())
        let place = CompassLocation(position: .zero, isKnown: true, opacityPercent: 100)
        hud.updateCompassLocations([place])
        #expect(hud.compassLocations == [place])
        hud.updateCompassLocations([])
        #expect(hud.compassLocations.isEmpty)
    }
}
