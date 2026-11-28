// The flanking loop of a style with the flanking flag: the stalk, then the flank, chase,
// flank distant, and watch choices. Rules: docs/engine/combat-movement.md#flanking.

@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import simd
import Testing

@MainActor
struct CombatFlankingTests {
    private typealias Fixture = CombatBehaviorFixture

    /// A flanker that never attacks, with a short stalk.
    private static func flanker(stalkSeconds: Float = 0.5) -> CombatBehaviorMachine {
        var tuning = CombatStyleTuning.neutral
        tuning.flanks = true
        var settings = Fixture.neverCasting.tuned(by: tuning)
        settings.attackChance = 0
        settings.blockLoop = nil
        settings.flank?.stalkSeconds = stalkSeconds
        return Fixture.machine(settings: settings)
    }

    private static func inputs(distance: Float, goal: Float? = 0.5) -> CombatBehaviorInputs {
        var inputs = Fixture.inputs(distance: distance)
        inputs.place = CombatPlaceInputs(
            bearing: 0, halfWidth: 0.3, isOutOfPosition: true, canBookHere: false,
            goalBearing: goal
        )
        return inputs
    }

    @Test func theFlagAndTheCloseRangeValuesSetTheLoop() throws {
        let style = try CombatStyle(record: ESMFixture.record("CSTY", fields: [
            ("CSCR", ESMFixture.f32(0.2, 0.2, 0.5, 1)), ("DATA", ESMFixture.u32(0x02))
        ]))
        let tuning = CombatStyleTuning(style: style)
        #expect(tuning.flanks)
        let flank = CombatBehaviorSettings.standard.tuned(by: tuning).flank
        #expect(flank?.flankDistance == 512)
        #expect(flank?.stalkSeconds == 10)
        #expect(CombatBehaviorSettings.standard.tuned(by: .neutral).flank == nil)
        let limits = try #require(flank)
        #expect(limits.angleLimit(beyondReach: 384) == nil)
        #expect(abs((limits.angleLimit(beyondReach: 704) ?? 0) - 20 * .pi / 180) < 0.001)
        #expect(abs((limits.angleLimit(beyondReach: 5000) ?? 0) - 30 * .pi / 180) < 0.001)
    }

    @Test func aStalkInTheBandEndsInAFlankToAFreePlace() {
        var machine = Self.flanker()
        let near = Self.inputs(distance: Fixture.reach + 100)
        Fixture.run(&machine, until: { $0.closeMoveKind == "stalk" }, limit: 1, inputs: near)
        let steps = Fixture.run(
            &machine, until: { $0.closeMoveKind == "flank" }, limit: 2, inputs: near
        )
        #expect(machine.closeMoveKind == "flank")
        #expect(steps.last?.booksPlace == 0.5)
        guard case let .reposition(point)? = steps.last?.command else {
            Issue.record("no flank move")
            return
        }
        #expect(abs(atan2f(point.y, point.x) - 0.5) < 0.001)
        var arrived = near
        arrived.actorPosition = point
        Fixture.run(&machine, seconds: 0.05, inputs: arrived)
        #expect(machine.closeMoveKind != "flank")
        var short = Self.flanker()
        Fixture.run(&short, until: { $0.closeMoveKind == "flank" }, limit: 2, inputs: near)
        var outside = near
        outside.actorPosition = point * 1.2
        Fixture.run(&short, seconds: 0.05, inputs: outside)
        #expect(short.closeMoveKind == "chase")
    }

    @Test func aStalkJogsBackIntoItsBand() {
        var machine = Self.flanker(stalkSeconds: 5)
        let near = Self.inputs(distance: Fixture.reach + 100)
        Fixture.run(&machine, until: { $0.closeMoveKind == "stalk" }, limit: 1, inputs: near)
        let away = Self.inputs(distance: Fixture.reach + 300)
        let out = Fixture.run(&machine, seconds: 0.1, inputs: away)
        #expect(out.contains { $0.pace == .fastWalk })
        let back = Fixture.run(&machine, seconds: 0.1, inputs: near)
        #expect(back.contains { $0.command == .hold })
        let close = Self.inputs(distance: Fixture.reach - 50)
        #expect(!Fixture.run(&machine, seconds: 0.1, inputs: close).contains { $0.pace != nil })
    }

    @Test func farOffAWideGoalFailsAndTheChaseThenTheDistantFlankRun() {
        var machine = Self.flanker()
        let far = Self.inputs(distance: Fixture.reach + 1000, goal: 1)
        let steps = Fixture.run(&machine, until: { $0.closeMoveKind == "chase" }, inputs: far)
        guard case .approach? = steps.last?.command else {
            Issue.record("no chase")
            return
        }
        machine.noteAdvance(reached: false)
        let distant = Fixture.run(&machine, seconds: 0.05, inputs: far)
        #expect(machine.closeMoveKind == "flankDistant")
        #expect(distant.contains { $0.pace == .run })
        #expect(machine.refuseCloseMove() == nil)
        let watch = Fixture.run(&machine, seconds: 0.05, inputs: far)
        #expect(machine.closeMoveKind == "watch")
        #expect(watch.contains { $0.command == .hold })
        Fixture.run(&machine, seconds: 1.1, inputs: far)
        #expect(machine.closeMoveCount >= 4)
    }

    @Test func aFleeEndsTheLoop() {
        var machine = Self.flanker()
        let near = Self.inputs(distance: Fixture.reach + 100)
        Fixture.run(&machine, until: { $0.closeMoveKind == "stalk" }, limit: 1, inputs: near)
        var hurt = near
        hurt.healthFraction = 0
        Fixture.run(&machine, seconds: 0.05, inputs: hurt)
        #expect(machine.closeMoveKind == nil)
    }
}
