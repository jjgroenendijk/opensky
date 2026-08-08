// The scripted opponent's attack clock (issue #374, roadmap item 15.7).
//
// A pure value over a fixed step, so every test here is arithmetic: no world,
// no clock, no fake. What is being pinned is that the phase machine reaches
// contact exactly once per attack, that a stagger takes the attack away, and
// that the whole sequence is identical on a repeat run — the determinism the
// milestone gate depends on.

@testable import opensky
import Testing

struct DevTargetDriverTests {
    private static let step: Float = 1.0 / 60

    /// Advances `driver` for `seconds` and answers every step it reported.
    private static func run(
        _ driver: inout DevTargetDriver,
        seconds: Float
    ) -> [DevTargetStep] {
        var steps: [DevTargetStep] = []
        var elapsed: Float = 0
        while elapsed < seconds {
            steps.append(driver.step(seconds: step))
            elapsed += step
        }
        return steps
    }

    @Test func aDisabledDriverNeverLeavesIdle() {
        var driver = DevTargetDriver()
        let steps = Self.run(&driver, seconds: 10)
        #expect(steps.allSatisfy { $0 == .idle })
        #expect(driver.attackCount == 0)
        #expect(driver.contactCount == 0)
    }

    @Test func oneAttackReachesContactExactlyOnce() {
        var driver = DevTargetDriver()
        driver.isEnabled = true
        let seconds = DevTargetDriver.intervalSeconds
            + DevTargetDriver.windupSeconds
            + DevTargetDriver.recoverySeconds
        let steps = Self.run(&driver, seconds: seconds)

        #expect(steps.count { $0.startedAttack } == 1)
        #expect(steps.count { $0.reachedContact } == 1)
        #expect(driver.attackCount == 1)
        #expect(driver.contactCount == 1)
    }

    @Test func contactFollowsTheWindupAndNotTheAttackStart() {
        var driver = DevTargetDriver()
        driver.isEnabled = true
        let steps = Self.run(&driver, seconds: 4)
        guard
            let start = steps.firstIndex(where: \.startedAttack),
            let contact = steps.firstIndex(where: \.reachedContact)
        else {
            Issue.record("the driver never attacked")
            return
        }
        let gap = Float(contact - start) * Self.step
        // Within one step of the declared windup, which is the most a fixed
        // step can promise.
        #expect(abs(gap - DevTargetDriver.windupSeconds) <= Self.step)
    }

    @Test func theAttackCadenceRepeats() {
        var driver = DevTargetDriver()
        driver.isEnabled = true
        let cycle = DevTargetDriver.intervalSeconds
            + DevTargetDriver.windupSeconds
            + DevTargetDriver.recoverySeconds
        let steps = Self.run(&driver, seconds: cycle * 3 + Self.step)
        #expect(steps.count { $0.reachedContact } == 3)
    }

    @Test func aStaggerTakesTheAttackAwayBeforeItConnects() {
        var driver = DevTargetDriver()
        driver.isEnabled = true
        // Into the windup, then interrupted.
        _ = Self.run(&driver, seconds: DevTargetDriver.intervalSeconds + Self.step * 2)
        #expect(driver.phase == .windup)
        // Bound first: `stagger()` is mutating, and `#expect` evaluates its
        // argument inside a closure that cannot mutate a local.
        let staggered = driver.stagger()
        #expect(staggered)
        #expect(driver.phase == .staggered)

        // The interrupted attack never reaches contact, and the next one only
        // starts after the stagger and a fresh interval.
        let steps = Self.run(&driver, seconds: DevTargetDriver.staggerSeconds - Self.step * 2)
        #expect(!steps.contains { $0.reachedContact })
        #expect(driver.contactCount == 0)
        #expect(driver.attackCount == 1)
    }

    @Test func aSecondStaggerWhileStaggeringIsRefused() {
        var driver = DevTargetDriver()
        driver.isEnabled = true
        _ = Self.run(&driver, seconds: DevTargetDriver.intervalSeconds + Self.step)
        let first = driver.stagger()
        let second = driver.stagger()
        #expect(first)
        #expect(!second)
    }

    @Test func parkingReturnsToIdleAndKeepsTheCounts() {
        var driver = DevTargetDriver()
        driver.isEnabled = true
        _ = Self.run(&driver, seconds: 4)
        let attacks = driver.attackCount
        #expect(attacks > 0)

        driver.park()
        #expect(driver.phase == .idle)
        #expect(driver.attackCount == attacks)

        driver.reset()
        #expect(driver.attackCount == 0)
        // Reset keeps the driver enabled: the panel's reset restarts the fight
        // rather than ending it.
        #expect(driver.isEnabled)
    }

    @Test func twoRunsOfTheSameLengthProduceTheSameSequence() {
        var first = DevTargetDriver()
        var second = DevTargetDriver()
        first.isEnabled = true
        second.isEnabled = true
        #expect(Self.run(&first, seconds: 12) == Self.run(&second, seconds: 12))
        #expect(first == second)
    }
}
