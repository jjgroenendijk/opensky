// The HUD sends its meters and the enemy bar only when they change.

import OpenSkyFormatsSWF
import OpenSkyGameData
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

@MainActor
struct HUDCoordinatorMetersTests {
    @Test func metersAndTheEnemyBarAreKeptUntilTheyChange() {
        let hud = HUDCoordinator(movies: SWFMovieSource())
        let enemy = HUDEnemyHealth(name: "Bandit", health: 0.5)
        hud.publishMeters(ActorValues(repeating: 1), enemy: enemy)
        #expect(hud.publishedEnemy == enemy)
        hud.publishMeters(ActorValues(repeating: 1), enemy: nil)
        #expect(hud.publishedEnemy == nil)
    }
}
