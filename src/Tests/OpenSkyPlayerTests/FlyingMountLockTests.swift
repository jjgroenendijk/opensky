// The flying-mount lock's steering: the strafe term, the target term, and the fade
// with distance (docs/engine/combat-assist.md#flying-mount-lock).

@testable import OpenSkyPlayer
import Testing

struct FlyingMountLockTests {
    private func frame(strafe: Float = 0, distance: Float = 0) -> FlyingMountLock.Frame {
        var frame = FlyingMountLock.Frame()
        frame.speed = 700
        frame.strafe = strafe
        frame.distance = distance
        frame.deltaTime = 1
        return frame
    }

    @Test func theStrafeTermIsSpeedTimesStrafeOver350() {
        #expect(FlyingMountLock.strafeTerm(frame(strafe: 1)) == 2)
        #expect(FlyingMountLock.strafeTerm(frame(strafe: -0.5)) == -1)
    }

    @Test func aStillTargetHasNoTargetTerm() {
        #expect(FlyingMountLock.targetTerm(frame()) == 0)
    }

    @Test func theTargetTermFoldsTheAngleIntoAQuarterTurn() {
        var moving = frame()
        moving.targetVelocity = SIMD2(0, 350)
        #expect(abs(FlyingMountLock.targetTerm(moving) + 1) < 0.0001)
        moving.targetVelocity = SIMD2(-350, 0.0001)
        #expect(abs(FlyingMountLock.targetTerm(moving)) < 0.001)
    }

    @Test func theSteeringFadesToNothingAt750Units() {
        #expect(FlyingMountLock.headingChange(frame(strafe: 1)) == -1)
        #expect(abs(FlyingMountLock.headingChange(frame(strafe: 1, distance: 375)) + 0.5) < 0.0001)
        #expect(FlyingMountLock.headingChange(frame(strafe: 1, distance: 750)) == 0)
        #expect(FlyingMountLock.headingChange(frame(strafe: 1, distance: 2000)) == 0)
    }

    @Test func theOrdersTrackTheTargetsTravel() {
        var orders = RiddenDragonOrders()
        let rider = (feet: SIMD3<Float>.zero, yaw: Float(0))
        let first = orders.steer(
            toward: SIMD3(300, 0, 0), from: rider, input: (700, 0), deltaTime: 1
        )
        #expect(first == 0, "no travel is known at the first step, and no input is held")
        let second = orders.steer(
            toward: SIMD3(300, 350, 0), from: rider, input: (700, 0), deltaTime: 1
        )
        #expect(second < 0)
        #expect(orders.lockSteer == second)
        orders.weaponDrawn = false
        let sheathed = orders.steer(
            toward: SIMD3(100, 0, 0), from: rider, input: (700, 1), deltaTime: 1
        )
        #expect(sheathed == 0 && orders.lockSteer == 0)
        orders.weaponDrawn = true
        let gone = orders.steer(toward: nil, from: rider, input: (700, 1), deltaTime: 1)
        #expect(gone == 0)
    }
}
