// The bow zoom rule: block while aiming zooms with Eagle Eye, Slow Time blocks the start,
// and `bowZoomStop` holds it off until block comes up.

@testable import OpenSkyCombat
import Testing

struct BowZoomTests {
    private static let aiming = BowZoomInput(blockHeld: true, aiming: true, viewShare: 0.6)

    @Test func blockWhileAimingZoomsOnlyWithThePerk() {
        var zoom = BowZoom()
        zoom.update(Self.aiming)
        #expect(zoom.isZoomed)
        #expect(zoom.viewShare == 0.6)
        var noPerk = Self.aiming
        noPerk.viewShare = 1
        zoom.update(noPerk)
        #expect(!zoom.isZoomed)
        #expect(zoom.viewShare == 1)
    }

    @Test func slowTimeBlocksTheStartButNotARunningZoom() {
        var slowed = Self.aiming
        slowed.timeIsSlowed = true
        var zoom = BowZoom()
        zoom.update(slowed)
        #expect(!zoom.isZoomed)
        zoom.update(Self.aiming)
        zoom.update(slowed)
        #expect(zoom.isZoomed)
    }

    @Test func noStaminaOrNoAimEndsTheZoom() {
        var zoom = BowZoom()
        zoom.update(Self.aiming)
        var tired = Self.aiming
        tired.hasStamina = false
        zoom.update(tired)
        #expect(!zoom.isZoomed)
        zoom.update(Self.aiming)
        var lowered = Self.aiming
        lowered.aiming = false
        zoom.update(lowered)
        #expect(!zoom.isZoomed)
    }

    @Test func aStopHoldsUntilBlockComesUp() {
        var zoom = BowZoom()
        zoom.update(Self.aiming)
        zoom.stop()
        zoom.update(Self.aiming)
        #expect(!zoom.isZoomed)
        zoom.update(BowZoomInput(aiming: true, viewShare: 0.6))
        zoom.update(Self.aiming)
        #expect(zoom.isZoomed)
    }
}
