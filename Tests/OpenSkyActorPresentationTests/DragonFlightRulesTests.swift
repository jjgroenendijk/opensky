// The flight rules: take-off, the circle, the hover, and the landing with its approach.

@testable import OpenSkyActorPresentation
import OpenSkyBehavior
import simd
import Testing

struct DragonFlightRulesTests {
    private static let settings = DragonFlightSettings.standard
    private static let step: Float = 1.0 / 30

    /// Steps `seconds` toward `goal`, gathering every event.
    private static func fly(
        _ state: DragonFlightState, toward goal: DragonFlightGoal, seconds: Float,
        ground: @escaping DragonGroundHeight = { _ in 0 }
    ) -> (state: DragonFlightState, events: [DragonFlightEvent]) {
        var state = state
        var events: [DragonFlightEvent] = []
        for _ in 0 ..< Int(seconds / step) {
            let result = DragonFlightRules.step(
                state, goal: goal, settings: settings, deltaTime: step, ground: ground
            )
            state = result.state
            events += result.events
        }
        return (state, events)
    }

    private static func cruising(at feet: SIMD3<Float>, yaw: Float = 0) -> DragonFlightState {
        var state = DragonFlightState(feet: feet, yaw: yaw, phase: .cruising)
        state.speed = settings.cruiseSpeed
        return state
    }

    @Test func takeOffClimbsAndEndsInCruising() {
        let ground = DragonFlightState(feet: SIMD3(0, 0, 0), yaw: 0)
        let goal = DragonFlightGoal.circle(center: SIMD3(0, 0, 0), radius: 4000)
        let first = Self.fly(ground, toward: goal, seconds: Self.step)
        #expect(first.events == [.takeOff])
        #expect(first.state.phase == .takingOff)
        let flown = Self.fly(
            first.state, toward: goal, seconds: Self.settings.takeOffSeconds + 0.5
        )
        #expect(flown.state.phase == .cruising)
        #expect(flown.state.feet.z > 1000)
        #expect(!flown.events.contains(.landed))
    }

    @Test func cruisingCirclesTheCentre() {
        let start = Self.cruising(at: SIMD3(4000, 0, 1500), yaw: .pi / 2)
        let goal = DragonFlightGoal.circle(center: SIMD3(0, 0, 0), radius: 4000)
        var state = start
        for _ in 0 ..< 20 {
            state = Self.fly(state, toward: goal, seconds: 1).state
            let distance = simd_length(SIMD2(state.feet.x, state.feet.y))
            #expect(distance > 2500 && distance < 5500)
        }
        #expect(state.phase == .cruising)
    }

    @Test func aHoverTurnsTowardThePointItFaces() {
        let start = Self.cruising(at: SIMD3(0, 0, 1500))
        let goal = DragonFlightGoal.hover(facing: SIMD3(0, 1_000_000, 0))
        let flown = Self.fly(start, toward: goal, seconds: 6)
        #expect(flown.events.first == .startHover)
        #expect(flown.state.phase == .hovering)
        #expect(abs(flown.state.yaw - .pi / 2) < 0.05)
        #expect(flown.state.speed < 1)
    }

    @Test func aLandingApproachesThenTouchesDownOnItsPoint() {
        let point = SIMD3<Float>(6000, 0, 0)
        let flown = Self.fly(
            Self.cruising(at: SIMD3(0, 0, 1500)),
            toward: .ground(point),
            seconds: 30
        )
        #expect(flown.events.first == .beginLanding)
        guard
            let approach = flown.events.firstIndex(of: .beginApproach),
            let landed = flown.events.firstIndex(of: .landed)
        else {
            Issue.record("no approach or touchdown: \(flown.events)")
            return
        }
        #expect(approach < landed)
        #expect(flown.state.phase == .grounded)
        #expect(simd_distance(flown.state.feet, point) <= DragonFlightRules.arrivalDistance * 2)
    }

    @Test func aHoverStopsBeforeItsLanding() {
        let hovering = DragonFlightState(feet: SIMD3(0, 0, 700), yaw: 0, phase: .hovering)
        let step = DragonFlightRules.step(
            hovering, goal: .ground(nil), settings: Self.settings, deltaTime: Self.step,
            ground: { _ in 0 }
        )
        #expect(step.events == [.stopHover, .beginLanding])
        #expect(step.state.phase == .landing)
    }

    @Test func onlyALandingBeforeItsApproachCanBeCalledOff() {
        let far = SIMD3<Float>(50000, 0, 0)
        let landing = Self.fly(
            Self.cruising(at: SIMD3(0, 0, 1500)),
            toward: .ground(far),
            seconds: 1
        )
        #expect(landing.state.phase == .landing && !landing.state.isApproaching)
        let circle = DragonFlightGoal.circle(center: SIMD3(0, 0, 0), radius: 4000)
        let called = Self.fly(landing.state, toward: circle, seconds: Self.step)
        #expect(called.events == [.cancelLanding])
        #expect(called.state.phase == .cruising)

        var approaching = landing.state
        approaching.isApproaching = true
        let kept = Self.fly(approaching, toward: circle, seconds: Self.step)
        #expect(kept.state.phase == .landing)
    }

    @Test func aFlightNeverSinksBelowTheGround() {
        let hill: DragonGroundHeight = { _ in 900 }
        let low = Self.cruising(at: SIMD3(0, 0, 0))
        let goal = DragonFlightGoal.circle(center: SIMD3(0, 0, 0), radius: 4000)
        let flown = Self.fly(low, toward: goal, seconds: 1, ground: hill)
        #expect(flown.state.feet.z >= 900)
    }

    @Test func aFlightWritesItsGraphInputs() {
        var state = Self.cruising(at: SIMD3(0, 0, 1500))
        state.verticalSpeed = 200
        let inputs = Dictionary(
            uniqueKeysWithValues: DragonFlightGraphNames.inputs(state, settings: Self.settings)
                .map { ($0.name, $0.value) }
        )
        #expect(inputs[DragonFlightGraphNames.targetSpeed] == .real(Self.settings.cruiseSpeed))
        #expect(inputs[DragonFlightGraphNames.isOnGround] == .bool(false))
        #expect(inputs[DragonFlightGraphNames.distanceToGoal]
            == .real(DragonFlightGraphNames.noGoalDistance))
        #expect(DragonFlightGraphNames.event(for: .beginApproach) == "FlyStopDefault")
        #expect(DragonFlightGraphNames.event(for: .takeOff) == "TakeOff")
        #expect(DragonFlightGraphNames.event(for: .beginLanding) == nil)
    }
}
