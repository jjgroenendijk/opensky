// A loose body that loses speed suddenly has hit something (docs/engine/impulses.md).

import OpenSkyCombat
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import simd
import Testing

struct BodyCollisionTrackerTests {
    private func body(speed: Float) -> ImpulseBody {
        ImpulseBody(
            key: .generated(3), reference: FormID(0x33), position: SIMD3(0, 0, 10),
            velocity: SIMD3(0, 0, -speed), mass: 10, boundingRadius: 5, kind: .clutter,
            material: FormID(0x44)
        )
    }

    @Test func aSuddenStopIsOneHit() {
        var tracker = BodyCollisionTracker()
        #expect(tracker.update([body(speed: 600)]).isEmpty)
        let hits = tracker.update([body(speed: 0)])
        #expect(hits.count == 1)
        #expect(hits.first?.speedLoss == 600)
        #expect(hits.first?.material == FormID(0x44))
        #expect(tracker.update([body(speed: 500)]).isEmpty)
        #expect(tracker.update([body(speed: 0)]).isEmpty)
    }

    @Test func gravityAndPushesStaySilent() {
        var tracker = BodyCollisionTracker()
        _ = tracker.update([body(speed: 100)])
        #expect(tracker.update([body(speed: 110)]).isEmpty)
        #expect(tracker.update([body(speed: 900)]).isEmpty)
        #expect(tracker.update([body(speed: 800)]).isEmpty)
    }

    @Test func aHarderHitIsLouder() {
        let soft = BodyCollision(
            body: .generated(1),
            position: .zero,
            speedLoss: 150,
            material: nil
        )
        let hard = BodyCollision(
            body: .generated(1),
            position: .zero,
            speedLoss: 2000,
            material: nil
        )
        #expect(soft.gain == BodyCollisionTracker.quietestGain)
        #expect(hard.gain == 1)
    }
}
