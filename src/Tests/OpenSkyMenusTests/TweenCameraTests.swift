// The Tween camera: the view widens by 10 degrees at 25 degrees a second, turns toward
// the highlighted entry, and eases back after the menu shuts.

@testable import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyRenderCore
import Testing

struct TweenCameraTests {
    @Test func theViewWidensByTenDegreesInFourTenthsOfASecond() {
        var camera = TweenCamera()
        camera.open()
        camera.step(dt: 0.2)
        #expect(abs(camera.offset.horizontalFOVDegrees - 5) < 0.001)
        camera.step(dt: 0.2)
        camera.step(dt: 0.2)
        #expect(camera.offset.horizontalFOVDegrees == 10)
    }

    @Test func theViewTurnsTowardTheHighlightedEntry() {
        var camera = TweenCamera()
        camera.open()
        camera.highlight(.magic)
        camera.step(dt: 0.1)
        #expect(abs(camera.offset.yaw - 0.02) < 0.0001, "4 per second eases 40 % of the gap")
        camera.step(dt: 1)
        #expect(camera.offset.yaw == 0.05, "a step past the gap lands on the target")
        camera.highlight(.map)
        camera.step(dt: 1)
        #expect(camera.offset.yaw == 0)
        #expect(camera.offset.pitch == -0.05)
    }

    @Test func closingEasesBackAndEnds() {
        var camera = TweenCamera()
        camera.open()
        camera.highlight(.skills)
        camera.step(dt: 1)
        camera.close()
        camera.highlight(.items)
        camera.step(dt: 0.2)
        #expect(camera.isActive)
        #expect(abs(camera.offset.horizontalFOVDegrees - 5) < 0.001)
        #expect(camera.offset.yaw == 0, "a highlight while closing does not turn the view")
        camera.step(dt: 0.2)
        #expect(!camera.isActive)
        #expect(camera.offset == .none)
    }

    @Test @MainActor func theMenuSendsTheMoveEachFrameUntilItEnds() {
        let world = FakeTweenWorld()
        let menu = TweenMenuCoordinator(menuMode: MenuModeController(), world: world)
        #expect(menu.open { _ in })
        menu.tick(now: 1)
        menu.tick(now: 1.5)
        #expect(world.viewOffsets.last?.horizontalFOVDegrees == 10)
        menu.route(.button(.cancel))
        menu.tick(now: 2)
        menu.tick(now: 2.5)
        #expect(world.viewOffsets.last == MenuViewOffset.none)
        let sent = world.viewOffsets.count
        menu.tick(now: 3)
        #expect(world.viewOffsets.count == sent, "nothing is sent once the move ends")
    }
}
