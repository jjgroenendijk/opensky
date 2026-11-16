// The grab spring's strength, its pull, and the rules that let go.

import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyPhysics
import simd
import Testing

struct GrabRulesTests {
    @Test func aHeavierBodyIsHeldWithLessForce() {
        let jointed = GrabStrength.of(.actor(totalMass: 90, jointed: true))
        #expect(abs(jointed.force - 0.52) < 1e-5)
        #expect(jointed.elasticity == 1)
        let heavy = GrabStrength.of(.actor(totalMass: 400, jointed: true))
        #expect(abs(heavy.force - 0.2) < 1e-5)
        let loose = GrabStrength.of(.actor(totalMass: 90, jointed: false))
        #expect(abs(loose.force - 0.104) < 1e-5)
        #expect(loose.elasticity == 0.1)
        #expect(GrabStrength.of(.object(trap: false)) == GrabStrength(force: 1, elasticity: 1))
        #expect(GrabStrength.of(.object(trap: true)) == GrabStrength(force: 0.5, elasticity: 0.1))
    }

    @Test func theTargetSitsAheadOfTheEyeAtTheHoldDistance() {
        let hold = GrabHold(
            strength: .of(.object(trap: false)), grabDistance: 10, playerRadius: 18
        )
        #expect(hold.distance == 23)
        let eye = SIMD3<Float>(0, 0, 100)
        #expect(hold.target(eye: eye, look: SIMD3(2, 0, 0)) == SIMD3(23, 0, 100))
        #expect(hold.target(eye: eye, look: SIMD3(1, 0, 0), blocked: 8) == SIMD3(8, 0, 100))
    }

    @Test func theSpringPullsTowardTheTargetWithinItsForce() {
        let hold = GrabHold(
            strength: .of(.object(trap: false)), grabDistance: 100, playerRadius: 18
        )
        let moved = hold.velocity(
            position: .zero, velocity: .zero, target: SIMD3(10, 0, 0), dt: 1.0 / 60
        )
        #expect(moved.x > 0)
        let far = hold.velocity(
            position: .zero, velocity: .zero, target: SIMD3(1e6, 0, 0), dt: 1.0 / 60
        )
        // The change is capped at 100 m/s² for one 60th of a second, then damped.
        #expect(far.x <= 100 * 69.99 / 60 + 1e-2)
    }

    @Test func theHoldLetsGoWhenStretchedOrPinned() {
        let hold = GrabHold(
            strength: .of(.object(trap: false)), grabDistance: 100, playerRadius: 18
        )
        let target = SIMD3<Float>(0, 0, 0)
        #expect(hold.letsGo(
            target: target, held: SIMD3(97, 0, 0), objectMass: 10, heaviestContact: nil
        ))
        #expect(!hold.letsGo(
            target: target, held: SIMD3(50, 0, 0), objectMass: 10, heaviestContact: 30
        ))
        #expect(hold.letsGo(
            target: target, held: SIMD3(50, 0, 0), objectMass: 10, heaviestContact: 41
        ))
        #expect(!hold.letsGo(
            target: target, held: SIMD3(5, 0, 0), objectMass: 10, heaviestContact: 1000
        ))
    }
}

struct GrabUseKeyTests {
    @Test func aTapActivatesAndAHoldGrabs() {
        var key = GrabUseKey()
        let onNothing = key.press(onGrabbable: false)
        #expect(!onNothing)
        let firstPress = key.press(onGrabbable: true)
        let tap = key.advance(by: 0.1, isDown: false)
        #expect(firstPress && tap == .tap)
        let secondPress = key.press(onGrabbable: true)
        let early = key.advance(by: 0.1, isDown: true)
        let late = key.advance(by: 0.15, isDown: true)
        #expect(secondPress && early == nil && late == .grab)
        #expect(key.isHolding)
    }

    @Test func releasingTheStartingKeyKeepsHoldingAndASecondPressLetsGo() {
        var key = GrabUseKey()
        _ = key.press(onGrabbable: true)
        _ = key.advance(by: 0.3, isDown: true)
        let release = key.advance(by: 0.1, isDown: false)
        #expect(release == nil && key.isHolding)
        let again = key.press(onGrabbable: false)
        let down = key.advance(by: 0.1, isDown: true)
        let up = key.advance(by: 0.1, isDown: false)
        #expect(again && down == nil && up == .letGo)
        #expect(!key.isHolding)
    }

    @Test func theTwoForceSettingsComeFromTheGameSettings() throws {
        let file = try GameSettingFixture.plugin(settings: [
            "fZKeyMaxForce": .float(80), "fZKeyMaxForceWeightHigh": .float(120)
        ])
        let settings = GrabSettings.resolve(store: GameSettingStore(plugins: [("Grab.esp", file)]))
        #expect(settings.maxForce == 80)
        #expect(settings.weightHigh == 120)
        #expect(GrabSettings.resolve(store: GameSettingStore(plugins: [])).maxForce == 100)
    }

    @Test func anIdleKeyReportsNothingAndASecondPressWhileWaitingIsTaken() {
        var key = GrabUseKey(holdDelay: 0.25)
        let idle = key.advance(by: 0.1, isDown: false)
        let first = key.press(onGrabbable: true)
        let second = key.press(onGrabbable: true)
        #expect(idle == nil && first && second)
        #expect(!key.isHolding)
    }
}
