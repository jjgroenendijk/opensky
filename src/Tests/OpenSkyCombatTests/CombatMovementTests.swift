// The moves of a styled NPC beside its close-range loop: places around the target, the
// reposition, the surround and distant circle after a failed advance, and the archer
// strafe. Rules: docs/engine/combat-movement.md.

@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
import OpenSkyFormatsESM
import simd
import Testing

@MainActor
struct CombatMovementTests {
    private typealias Fixture = CombatBehaviorFixture

    /// A styled melee actor that never attacks, blocks, or casts.
    private static func styled(
        _ edit: (inout CombatBehaviorSettings) -> Void = { _ in }
    ) -> CombatBehaviorMachine {
        var settings = Fixture.neverCasting.tuned(by: .neutral)
        settings.attackChance = 0
        settings.blockLoop = nil
        edit(&settings)
        return Fixture.machine(settings: settings)
    }

    @discardableResult
    private static func run(
        _ machine: inout CombatBehaviorMachine, seconds: Float, inputs: CombatBehaviorInputs,
        reached: Bool = false
    ) -> [CombatBehaviorStep] {
        var steps: [CombatBehaviorStep] = []
        var elapsed: Float = 0
        while elapsed < seconds {
            let step = machine.step(seconds: Fixture.step, inputs: inputs)
            if case .approach? = step.command {
                machine.noteAdvance(reached: reached)
            }
            steps.append(step)
            elapsed += Fixture.step
        }
        return steps
    }

    private static func repositions(_ steps: [CombatBehaviorStep]) -> [SIMD3<Float>] {
        steps.compactMap {
            if case let .reposition(point)? = $0.command {
                return point
            }
            return nil
        }
    }

    @Test func anArcFollowsTheFightersSizeAndDistance() {
        let half = CombatPlaceBook.halfWidth(radius: 30, distance: 250)
        #expect(abs(half - 0.24) < 0.001)
        #expect(CombatPlaceBook.halfWidth(radius: 1, distance: 10000) * 2 > 0.174)
        #expect(abs(CombatPlaceBook.halfWidth(radius: 500, distance: 1) - .pi / 2) < 0.001)
        var book = CombatPlaceBook()
        let first = ReferenceKey.generated(1)
        let second = ReferenceKey.generated(2)
        #expect(book.isOutOfPosition(first, bearing: 0))
        let booked = book.book(.init(centre: 0, halfWidth: half), for: first)
        #expect(booked)
        #expect(!book.isOutOfPosition(first, bearing: 0.15))
        #expect(book.isOutOfPosition(first, bearing: 0.17))
        let overlaps = book.book(.init(centre: 0.3, halfWidth: half), for: second)
        #expect(!overlaps)
        let free = book.freeBearing(near: 0, halfWidth: half, for: second)
        #expect(abs((free ?? 0) + 2 * .pi / 12) < 0.001)
        #expect(book.freeBearing(near: 0, halfWidth: .pi, for: second) == nil)
        book.keep { $0 == second }
        #expect(book.arcs.isEmpty)
    }

    @Test func aFailedAdvanceRunsToTheSurroundRingsMiddle() {
        var machine = Self.styled()
        let far = Fixture.inputs(distance: 2000)
        let steps = Self.run(&machine, seconds: 1.5, inputs: far)
        #expect(machine.pathMoveKind == "surround")
        let middle = Fixture.reach + machine.settings.backOffRadius + 256
        let point = Self.repositions(steps).first
        #expect(abs((point?.x ?? 0) - middle) < 0.01)
        #expect(steps.contains { $0.pace == .run })
        var arrived = far
        arrived.actorPosition = point ?? .zero
        Self.run(&machine, seconds: 0.1, inputs: arrived)
        #expect(machine.pathMoveKind == nil)
        #expect(machine.pathMoveCount == 1)
    }

    @Test func aReachedAdvanceNeverSurrounds() {
        var machine = Self.styled()
        Self.run(&machine, seconds: 3, inputs: Fixture.inputs(distance: 2000), reached: true)
        #expect(machine.pathMoveCount == 0)
    }

    @Test func insideTheRingTheNPCCirclesAndTriesTheOtherSideOnce() {
        var machine = Self.styled { $0.movement?.distantCircleChance = 1 }
        let ring = Fixture.inputs(distance: Fixture.reach + 256)
        let steps = Self.run(&machine, seconds: 1.5, inputs: ring)
        #expect(machine.pathMoveKind == "distantCircle")
        let point = Self.repositions(steps).first ?? .zero
        #expect(abs(simd_length(point) - ring.distance) < 0.5)
        #expect(abs(point.y) > 1)
        #expect(steps.contains { $0.pace == .fastWalk })
        let other = machine.refuseCloseMove()
        #expect(other.map { $0.y * point.y < 0 } == true)
        #expect(machine.refuseCloseMove() == nil)
        #expect(machine.pathMoveKind == nil)
    }

    @Test func noCircleRollWaitsAndThenAdvancesAgain() {
        var machine = Self.styled { $0.movement?.distantCircleChance = 0 }
        let ring = Fixture.inputs(distance: Fixture.reach + 256)
        Self.run(&machine, seconds: 1.2, inputs: ring)
        let steps = Self.run(&machine, seconds: 1.5, inputs: ring)
        #expect(machine.pathMoveCount == 0)
        #expect(steps.contains {
            if case .approach? = $0.command {
                true
            } else {
                false
            }
        })
    }

    @Test func theAdvanceWalksToAFreePlaceAndBooksIt() {
        var machine = Self.styled()
        var inputs = Fixture.inputs(distance: 2000)
        inputs.place = CombatPlaceInputs(
            bearing: 0, halfWidth: 0.3, isOutOfPosition: true, canBookHere: false,
            goalBearing: .pi / 2
        )
        let steps = Self.run(&machine, seconds: 0.1, inputs: inputs, reached: true)
        let approach = steps.first { $0.booksPlace != nil }
        #expect(approach?.booksPlace == .pi / 2)
        guard case let .approach(point)? = approach?.command else {
            Issue.record("no approach")
            return
        }
        let radius = Fixture.reach - machine.settings.reachSlack - 8
        #expect(abs(point.y - radius) < 0.01)
        #expect(abs(point.x) < 0.01)
    }

    @Test func nearItsPlaceTheAdvanceWalksStraightAtTheTarget() {
        var machine = Self.styled()
        var inputs = Fixture.inputs(distance: Fixture.reach + 100)
        inputs.place = CombatPlaceInputs(
            bearing: 0, halfWidth: 0.3, isOutOfPosition: true, canBookHere: false,
            goalBearing: .pi / 2
        )
        let steps = Self.run(&machine, seconds: 0.1, inputs: inputs, reached: true)
        let approach = steps.first { $0.booksPlace != nil }
        #expect(approach?.booksPlace == .pi / 2)
        #expect(approach?.command == .approach(inputs.targetPosition))
    }

    @Test func anNPCOutOfPositionBooksWhereItStandsOrRepositions() {
        var machine = Self.styled()
        var here = Fixture.inputs()
        here.place = CombatPlaceInputs(
            bearing: 0.2, halfWidth: 0.3, isOutOfPosition: true, canBookHere: true,
            goalBearing: 0.2
        )
        let steps = Self.run(&machine, seconds: 0.2, inputs: here)
        #expect(steps.contains { $0.booksPlace == 0.2 })
        var away = here
        away.place?.canBookHere = false
        away.place?.goalBearing = .pi
        let moved = Self.run(&machine, seconds: 0.2, inputs: away)
        #expect(machine.closeMoveKind == "reposition")
        #expect(moved.contains { $0.booksPlace == .pi })
        #expect(Self.repositions(moved).first.map { $0.x < 0 } == true)
        var arrived = away
        arrived.actorPosition = Self.repositions(moved).first ?? .zero
        arrived.place?.isOutOfPosition = false
        Self.run(&machine, seconds: 0.2, inputs: arrived)
        #expect(machine.closeMoveKind != "reposition")
    }

    /// An archer at its preferred range with a strafe chance of 1.
    private static func archer() -> (CombatBehaviorMachine, CombatBehaviorInputs) {
        var settings = Fixture.neverCasting.tuned(by: .neutral)
        settings.strafe?.chance = 1
        let range = NPCArcheryRange(style: .neutral, radius: 30)
        var inputs = Fixture.inputs(distance: range.preferred)
        inputs.archery = range
        inputs.reach = range.preferred + settings.reachSlack
        inputs.actorRadius = 30
        inputs.weaponOut = true
        return (Fixture.machine(settings: settings), inputs)
    }

    @Test func anArcherStrafesSidewaysAndKeepsGoingThroughTheDraw() {
        var (machine, inputs) = Self.archer()
        let steps = Fixture.run(&machine, until: { $0.pathMoveKind == "strafe" }, inputs: inputs)
        let point = Self.repositions(steps).last ?? .zero
        #expect(abs(point.x - inputs.distance) < 0.01)
        #expect(abs(point.y) >= 96 && abs(point.y) <= 256)
        #expect(steps.last?.pace == .fastWalk)
        Fixture.run(&machine, until: { $0.phase == .windup }, limit: 5, inputs: inputs)
        #expect(machine.pathMoveKind == "strafe")
        var arrived = inputs
        arrived.actorPosition = point
        Fixture.run(&machine, until: { $0.pathMoveKind == nil }, limit: 5, inputs: arrived)
        #expect(machine.pathMoveKind == nil)
    }

    @Test func aStrafeThatNeverArrivesStopsAfterFiveSeconds() {
        var (machine, inputs) = Self.archer()
        Fixture.run(&machine, until: { $0.pathMoveKind == "strafe" }, inputs: inputs)
        let steps = Fixture.run(
            &machine, until: { $0.pathMoveKind != "strafe" }, limit: 6, inputs: inputs
        )
        #expect(steps.contains { $0.command == .hold })
    }

    @Test func aStyleSetsTheMovementAndStrafeSettings() {
        var tuning = CombatStyleTuning.neutral
        tuning.circleMultiplier = 1
        tuning.strafeMultiplier = 1
        let settings = CombatBehaviorSettings.standard.tuned(by: tuning)
        #expect(settings.movement?.distantCircleChance == 0.75)
        #expect(settings.movement?.distantCircleAngle.max == 90)
        #expect(settings.strafe?.chance == 0.75)
        #expect(CombatBehaviorSettings.standard.movement == nil)
    }
}
