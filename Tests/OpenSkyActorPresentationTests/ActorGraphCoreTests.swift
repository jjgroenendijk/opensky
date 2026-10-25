// The rules of the per-actor behaviour graphs: the distance cutoff, the locomotion events a
// change of motion raises, the variables a step writes, and the race graph path.

@testable import OpenSkyActorPresentation
import OpenSkyBehavior
import Testing

struct ActorGraphCoreTests {
    @Test func aGraphStepsEveryFrameNearAndLessOftenFurtherOut() {
        let cutoff = ActorGraphCutoff.standard
        #expect(cutoff.stepInterval(atDistance: 100) == 0)
        #expect(cutoff.stepInterval(atDistance: 3000) == ActorGraphCutoff.reducedStepInterval)
        #expect(cutoff.stepInterval(atDistance: 7000) == nil)
    }

    @Test func theGraphDistanceIsNeverInsideTheFullRateDistance() {
        let cutoff = ActorGraphCutoff(fullRateDistance: 4000, maximumDistance: 1000)
        #expect(cutoff.maximumDistance == 4000)
    }

    @Test func aChangeOfMotionRaisesTheLocomotionEvents() {
        let sprinting = ActorGraphMotion(isMoving: true, isSprinting: true)
        #expect(ActorGraphCore.events(from: .still, to: sprinting) == ["moveStart", "SprintStart"])
        #expect(ActorGraphCore.events(from: sprinting, to: .still) == ["moveStop", "SprintStop"])
        let sneaking = ActorGraphMotion(isSneaking: true)
        #expect(ActorGraphCore.events(from: .still, to: sneaking) == ["SneakStart"])
        #expect(ActorGraphCore.events(from: .still, to: .still).isEmpty)
    }

    @Test func theCombatStanceIsAnIntAndAChangeRaisesItsEvent() {
        let drawn = ActorGraphMotion(isInCombatStance: true)
        #expect(ActorGraphCore.events(from: .still, to: drawn) == ["combatStanceStart"])
        #expect(ActorGraphCore.events(from: drawn, to: .still) == ["combatStanceStop"])
        let input = ActorGraphStepInput(motion: drawn, speed: 0, turnDelta: 0, deltaTime: 0.1)
        let stance = ActorGraphCore.variables(input).first { $0.name == "iCombatStance" }?.value
        #expect(stance == .int(1))
    }

    @Test func aStandingActorWritesNoSpeed() {
        let input = ActorGraphStepInput(motion: .still, speed: 120, turnDelta: 0, deltaTime: 0.1)
        let speed = ActorGraphCore.variables(input).first { $0.name == "Speed" }?.value
        #expect(speed == .real(0))
        let npc = ActorGraphCore.variables(input).first { $0.name == "IsNPC" }?.value
        #expect(npc == .bool(true))
    }

    @Test func speedIsHorizontalTravelPerSecond() {
        #expect(ActorGraphCore.speed(from: [0, 0, 0], to: [30, 40, 99], seconds: 0.5) == 100)
        #expect(ActorGraphCore.speed(from: [0, 0, 0], to: [30, 40, 0], seconds: 0) == 0)
    }

    @Test func aTurnTakesTheShortWayRound() {
        let turn = ActorGraphCore.turnDelta(from: 3, to: -3)
        #expect(abs(turn - (2 * Float.pi - 6)) < 0.0001)
    }

    @Test func theRaceGraphPathIsUnderMeshes() {
        #expect(
            ActorGraphCore.projectPath(modelPath: "Actors/Canine/WolfProject.hkx")
                == "meshes\\actors\\canine\\wolfproject.hkx"
        )
    }
}
