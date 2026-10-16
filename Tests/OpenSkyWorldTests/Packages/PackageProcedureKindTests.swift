// The procedure machines of the kinds that act or watch: door locks, finds,
// acquire, wait, say, follow, flee, escort, use weapon, and force greet.

@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
import simd
import Testing

struct PackageProcedureKindTests {
    static let first = PackageRuntimeFixture.key(0x900)
    static let second = PackageRuntimeFixture.key(0x901)
    static let place = SIMD3<Float>(500, 0, 0)

    private static func machine(
        _ kind: PackageProcedureKind, _ change: (inout PackageProcedureSetup) -> Void = { _ in }
    ) -> PackageProcedureMachine {
        var setup = PackageProcedureSetup(kind: kind, center: place, radius: 300)
        change(&setup)
        return PackageProcedureMachine(setup: setup)
    }

    @Test func lockDoorsActsWithoutAWalk() {
        var machine = Self.machine(.lockDoors)
        #expect(machine.start() == [.act(.setDoorsLocked(true, center: Self.place, radius: 300))])
        _ = machine.handle(.acted(.done))
        #expect(machine.state == .complete)
    }

    @Test func aFindThatFoundNothingLooksAgain() {
        let selector = Package.Target(rawKind: 2, value: 26, countOrDistance: 0)
        var machine = Self.machine(.find) { $0.selector = selector }
        let look = PackageProcedureCommand.act(.find(selector, center: Self.place, radius: 300))
        #expect(machine.start() == [look])
        _ = machine.handle(.acted(.found([])))
        #expect(machine.state == .searching(retrySeconds: 2))
        #expect(machine.handle(.tick(2)) == [look])
        _ = machine.handle(.acted(.found([Self.first])))
        #expect(machine.found == [Self.first])
        #expect(machine.state == .complete)
    }

    @Test func acquireTriesTheNextItemWhenOneFails() {
        var machine = Self.machine(.acquire) { $0.targets = [Self.first, Self.second] }
        #expect(machine.start() == [.move(to: Self.place)])
        #expect(machine.handle(.arrived) == [.act(.pickUp(Self.first))])
        #expect(machine.handle(.acted(.failed)) == [.move(to: Self.place)])
        #expect(machine.handle(.arrived) == [.act(.pickUp(Self.second))])
        _ = machine.handle(.acted(.failed))
        #expect(machine.state == .failed)
    }

    @Test func aTimedWaitEndsAfterItsSeconds() {
        var machine = Self.machine(.wait) { $0.seconds = 2 }
        _ = machine.start()
        _ = machine.handle(.tick(1))
        #expect(machine.state == .waiting)
        _ = machine.handle(.tick(1.5))
        #expect(machine.state == .complete)
    }

    @Test func aSpokenLineLastsItsLength() {
        var machine = Self.machine(.say) { $0.watched = Self.first }
        #expect(machine.start() == [.act(.say(topic: nil, to: Self.first))])
        _ = machine.handle(.acted(.lasts(seconds: 2)))
        _ = machine.handle(.tick(1))
        #expect(machine.state == .acting(secondsRemaining: 1))
        _ = machine.handle(.tick(1))
        #expect(machine.state == .complete)
    }

    /// A follower walks once its target is out of range, and not again for a small step.
    @Test func aFollowerWalksAfterItsTarget() {
        var machine = Self.machine(.follow) {
            $0.watched = Self.first
            $0.far = 200
        }
        #expect(machine.start().isEmpty)
        let target = SIMD3<Float>(500, 0, 0)
        #expect(machine
            .handle(.sensed(.init(actor: .zero, watched: target))) == [.move(to: target)])
        let step = SIMD3<Float>(550, 0, 0)
        #expect(machine.handle(.sensed(.init(actor: .zero, watched: step))).isEmpty)
        _ = machine.handle(.arrived)
        #expect(machine.state == .waiting)
    }

    @Test func aFleeRunsAwayUntilItIsFarEnough() {
        var machine = Self.machine(.flee) {
            $0.watched = Self.first
            $0.far = 1000
            $0.flag = true
        }
        _ = machine.start()
        let threat = SIMD3<Float>(100, 0, 0)
        #expect(machine.handle(.sensed(.init(actor: .zero, watched: threat)))
            == [.move(to: SIMD3(-1000, 0, 0))])
        let away = SIMD3<Float>(-1200, 0, 0)
        #expect(machine.handle(.sensed(.init(actor: away, watched: threat))) == [.stop])
        #expect(machine.state == .complete)
    }

    @Test func anEscortWaitsForItsCharge() {
        let goal = SIMD3<Float>(2000, 0, 0)
        var machine = Self.machine(.escort) {
            $0.watched = Self.first
            $0.destination = goal
            $0.far = 300
        }
        #expect(machine.start() == [.move(to: goal)])
        let behind = SIMD3<Float>(-500, 0, 0)
        #expect(machine.handle(.sensed(.init(actor: .zero, watched: behind))) == [.stop])
        let close = SIMD3<Float>(-100, 0, 0)
        #expect(machine.handle(.sensed(.init(actor: .zero, watched: close))) == [.move(to: goal)])
    }

    @Test func aRepeatFireAttackHoldsAfterItStarts() {
        var machine = Self.machine(.useWeapon) {
            $0.targets = [Self.first]
            $0.flag = true
            $0.startsCombat = true
        }
        _ = machine.start()
        #expect(machine.handle(.arrived) == [.act(.attack(Self.first, startsCombat: true))])
        _ = machine.handle(.acted(.done))
        #expect(machine.state == .waiting)
    }

    @Test func aGreeterWalksUpAndSpeaks() {
        var machine = Self.machine(.forceGreet) {
            $0.watched = .player
            $0.radius = 0
        }
        _ = machine.start()
        let player = SIMD3<Float>(1000, 0, 0)
        #expect(machine
            .handle(.sensed(.init(actor: .zero, watched: player))) == [.move(to: player)])
        let near = SIMD3<Float>(100, 0, 0)
        #expect(machine.handle(.sensed(.init(actor: .zero, watched: near)))
            == [.act(.forceGreet(topic: nil))])
    }

    @Test func everyCensusProcedureIsRunnable() {
        let names = [
            "UnlockDoors",
            "Find",
            "Acquire",
            "ForceGreet",
            "LockDoors",
            "Follow",
            "HoldPosition",
            "Guard",
            "Activate",
            "UseWeapon",
            "UseIdleMarker",
            "UseMagic",
            "Escort",
            "Orbit",
            "Shout",
            "KeepAnEyeOn",
            "Flee",
            "Hover",
            "Say",
            "FlightGrab",
            "FollowTo",
            "DialogueActivate"
        ]
        let runnable = PackageStore.runnableProcedures
        #expect(names.filter { !runnable.contains($0.lowercased()) }.isEmpty)
        #expect(PackageProcedureKind(name: "Teleport") == .unsupported("Teleport"))
    }
}
