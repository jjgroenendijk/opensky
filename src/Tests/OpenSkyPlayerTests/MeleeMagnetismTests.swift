// Melee magnetism: each term of the rule, what stops it, the tracker, and the actor
// the view ray picks (docs/engine/combat-assist.md#melee-magnetism).

import OpenSkyFormatsESM
import OpenSkyPhysics
@testable import OpenSkyPlayer
import OpenSkyWorldInterface
import simd
import Testing

struct MeleeMagnetismTests {
    private static let enemy = ReferenceKey.generated(7)

    /// A drawn weapon, an actor at the eye, a speed of 700, and a frame of one second.
    private func frame(strafe: Float = 0, distance: Float = 0) -> MeleeMagnetism.Frame {
        var frame = MeleeMagnetism.Frame()
        frame.speed = 700
        frame.strafe = strafe
        frame.distance = distance
        frame.deltaTime = 1
        frame.weaponDrawn = true
        frame.targetIsActor = true
        return frame
    }

    @Test func theStrafeTermIsSpeedTimesStrafeOver350() {
        #expect(MeleeMagnetism.strafeTerm(frame(strafe: 1)) == 2)
        #expect(MeleeMagnetism.strafeTerm(frame(strafe: -0.5)) == -1)
    }

    @Test func theTargetTermFoldsTheAngleIntoAQuarterTurn() {
        var moving = frame()
        #expect(MeleeMagnetism.targetTerm(moving) == 0, "a still target has no term")
        moving.targetVelocity = SIMD2(0, 350)
        #expect(abs(MeleeMagnetism.targetTerm(moving) + 1) < 0.0001)
        moving.targetVelocity = SIMD2(-350, 350)
        #expect(abs(MeleeMagnetism.targetTerm(moving) + 0.5 * Float(2).squareRoot()) < 0.0001)
        moving.targetVelocity = SIMD2(-350, 0.0001)
        #expect(abs(MeleeMagnetism.targetTerm(moving)) < 0.001)
        moving.targetIsActor = false
        moving.targetVelocity = SIMD2(0, 350)
        #expect(MeleeMagnetism.targetTerm(moving) == 0, "an object has no target term")
    }

    @Test func aStrafeAndAMovingTargetBothTurnTowardTheTarget() {
        #expect(MeleeMagnetism.change(frame(strafe: 1)).heading == 1, "right strafe, left turn")
        var moving = frame(strafe: 1)
        moving.targetVelocity = SIMD2(0, -700)
        #expect(abs(MeleeMagnetism.change(moving).heading) < 0.0001, "both move right: no turn")
        moving.strafe = 0
        moving.look = SIMD2(0.0001, 0)
        #expect(MeleeMagnetism.change(moving).heading < -0.9, "the target moves right")
    }

    @Test func theTurnFadesToNothingAt750Units() {
        #expect(MeleeMagnetism.fade(frame(distance: 375)) == 0.5)
        #expect(abs(MeleeMagnetism.change(frame(strafe: 1, distance: 375)).heading - 0.5) < 0.0001)
        #expect(MeleeMagnetism.change(frame(strafe: 1, distance: 750)) == .none)
        #expect(MeleeMagnetism.change(frame(strafe: 1, distance: 2000)) == .none)
    }

    @Test func theLookInputTurnsHeadingAndPitchByTheirFactors() {
        var looking = frame()
        looking.look = SIMD2(0.01, 0.02)
        looking.deltaTime = 0.5
        let actor = MeleeMagnetism.change(looking)
        #expect(abs(actor.heading - 0.01) < 0.00001, "0.01 x 2 x 0.5 s x 1")
        #expect(abs(actor.pitch - 0.2) < 0.00001, "0.02 x 2 x 0.5 s x 10")
        looking.targetIsActor = false
        looking.strafe = 1
        let object = MeleeMagnetism.change(looking)
        #expect(abs(object.heading - 0.005) < 0.00001, "an object's strafe factor is 0")
        #expect(abs(object.pitch - 0.01) < 0.00001)
    }

    @Test func theRuleStopsWithoutInputWhileRidingAndAtAnActorWithASheathedWeapon() {
        #expect(MeleeMagnetism.stops(frame()), "all inputs are zero")
        #expect(!MeleeMagnetism.stops(frame(strafe: 1)))
        var riding = frame(strafe: 1)
        riding.isRiding = true
        #expect(MeleeMagnetism.change(riding) == .none)
        var sheathed = frame(strafe: 1)
        sheathed.weaponDrawn = false
        #expect(MeleeMagnetism.change(sheathed) == .none)
        sheathed.targetIsActor = false
        sheathed.look = SIMD2(0.01, 0)
        #expect(MeleeMagnetism.change(sheathed) != .none, "an object needs no drawn weapon")
        var paused = frame(strafe: 1)
        paused.deltaTime = 0
        #expect(MeleeMagnetism.change(paused) == .none)
    }

    @Test func theTrackerReadsTheTargetsTravelAndKeepsTheLastTurn() {
        var tracker = MeleeMagnetismTracker()
        var held = frame()
        held.look = SIMD2(0.0001, 0)
        let first = MeleeMagnetism.Sighting(actor: Self.enemy, position: SIMD3(300, 0, 0))
        let still = tracker.step(held, sighting: first, eye: .zero)
        #expect(abs(still.heading) < 0.001, "no travel is known at the first sighting")
        let moved = MeleeMagnetism.Sighting(actor: Self.enemy, position: SIMD3(300, 350, 0))
        let turn = tracker.step(held, sighting: moved, eye: .zero)
        #expect(turn.heading > 0.1, "the target moved left, so the view turns left")
        #expect(tracker.isTurning && tracker.lastTarget == moved && tracker.lastChange == turn)
        let gone = tracker.step(held, sighting: nil, eye: .zero)
        #expect(gone == .none && !tracker.isTurning && tracker.lastChange == turn)
        tracker.isEnabled = false
        #expect(tracker.step(frame(strafe: 1), sighting: moved, eye: .zero) == .none)
    }

    @Test func theViewRayPicksTheNearestActorItPassesThrough() throws {
        let ray = try #require(InteractionRay(
            origin: SIMD3(0, 0, 64), direction: SIMD3(1, 0, 0), maximumDistance: 750
        ))
        let near = MeleeTarget(key: .generated(1), feet: SIMD3(400, 5, 0))
        let far = MeleeTarget(key: .generated(2), feet: SIMD3(600, 0, 0))
        let aside = MeleeTarget(key: .generated(3), feet: SIMD3(200, 100, 0))
        let beyond = MeleeTarget(key: .generated(4), feet: SIMD3(900, 0, 0))
        let hit = MeleeMagnetismPick.nearestActor(along: ray, actors: [far, aside, near, beyond])
        #expect(hit?.key == .generated(1))
        #expect(abs((hit?.distance ?? 0) - 400) < 1)
        #expect(MeleeMagnetismPick.nearestActor(along: ray, actors: [aside, beyond]) == nil)
    }
}
