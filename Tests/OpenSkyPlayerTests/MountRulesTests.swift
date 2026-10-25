// Who the player may mount, how a ridden mount steers, and what a rider may not do.

@testable import OpenSkyPlayer
import OpenSkyRendering
import simd
import Testing

struct MountRulesTests {
    private static func candidate(_ change: (inout MountCandidate) -> Void = { _ in })
        -> MountCandidate
    {
        var candidate = MountCandidate()
        candidate.saddleBone = "SaddleBone"
        change(&candidate)
        return candidate
    }

    @Test func aHorseWithASaddleIsMounted() {
        #expect(MountRules.decide(Self.candidate(), isRiding: false)
            == .mount(.horse, saddleBone: "SaddleBone", steals: false))
        let owned = Self.candidate { $0.ownership = .other }
        #expect(MountRules.decide(owned, isRiding: false)
            == .mount(.horse, saddleBone: "SaddleBone", steals: true))
    }

    @Test func aRefusalNamesItsReason() {
        #expect(MountRules.decide(Self.candidate(), isRiding: true) == .refuse(.alreadyRiding))
        #expect(MountRules.decide(nil, isRiding: false) == .refuse(.notLoaded))
        let dead = Self.candidate { $0.isDead = true }
        let bare = Self.candidate { $0.saddleBone = nil }
        let ridden = Self.candidate { $0.isRidden = true }
        #expect(MountRules.decide(dead, isRiding: false) == .refuse(.dead))
        #expect(MountRules.decide(bare, isRiding: false) == .refuse(.noSaddle))
        #expect(MountRules.decide(ridden, isRiding: false) == .refuse(.ridden))
    }

    @Test func aDragonNeedsAllowMountActor() {
        let dragon = Self.candidate {
            $0.isDragon = true
            $0.saddleBone = "NPC Saddlebone"
        }
        #expect(MountRules.decide(dragon, isRiding: false) == .refuse(.needsPerk))
        var tamed = dragon
        tamed.allowMountActor = 1
        #expect(MountRules.decide(tamed, isRiding: false)
            == .mount(.dragon, saddleBone: "NPC Saddlebone", steals: false))
    }

    @Test func steeringTurnsAtTheTurnRateAndNeverBacksUp() {
        let ahead = MountRules.steer(
            heading: 0, forward: 1, right: 0, cameraYaw: 0, deltaTime: 0.1, turnRate: 1
        )
        #expect(ahead == MountSteer(heading: 0, throttle: 1))
        let back = MountRules.steer(
            heading: 0, forward: -1, right: 0, cameraYaw: 0, deltaTime: 0.1, turnRate: 1
        )
        #expect(abs(abs(back.heading) - 0.1) < 0.0001)
        #expect(back.throttle == 1)
        let still = MountRules.steer(
            heading: 0.5, forward: 0, right: 0, cameraYaw: 2, deltaTime: 0.1, turnRate: 1
        )
        #expect(still == MountSteer(heading: 0.5, throttle: 0))
    }

    @Test func aRiderKeepsWeaponsAndBowsOnly() {
        var input = CameraInput(dt: 0.1)
        input.attack = true
        input.sneak = true
        input.block = true
        input.shout = true
        input.jump = true
        let sword = MountRules.riderInput(input, rightHandType: 1)
        #expect(sword.attack && !sword.sneak && !sword.block && !sword.shout && !sword.jump)
        #expect(!MountRules.riderInput(input, rightHandType: 9).attack)
        #expect(!MountRules.riderInput(input, rightHandType: 0).attack)
        #expect(MountRules.isMountedWeapon(7) && MountRules.isMountedWeapon(12))
        #expect(!MountRules.isMountedWeapon(8) && !MountRules.isMountedWeapon(10))
    }

    @Test func theRiderStepsOffOnTheLeft() {
        let side = MountRules.dismountPosition(offset: SIMD3(-50, 0, 65), yaw: .pi / 2)
        #expect(abs(side.x + 50) < 0.001 && abs(side.y) < 0.001)
    }

    @Test func theStanceIsAnIntAndAChangeRaisesItsEvent() {
        #expect(MountGraphNames.combatStanceValue(true) == 1)
        #expect(MountGraphNames.combatStanceEvent(from: false, to: true) == "combatStanceStart")
        #expect(MountGraphNames.combatStanceEvent(from: true, to: false) == "combatStanceStop")
        #expect(MountGraphNames.combatStanceEvent(from: true, to: true) == nil)
    }
}
