// Shared inputs for the two combat-behavior suites (issue #424).
//
// The machine is one type with two files of cases — the cadence half and the
// retreat half — because the strict lint type cap is smaller than the behaviour
// is. The literals both halves hand it live here so neither file owns them.

@testable import opensky
import simd

@MainActor
enum CombatBehaviorFixture {
    static let step = CombatLoopRuntime.fixedStepSeconds
    static let settings = CombatBehaviorSettings.standard
    /// Well inside reach, so distance never decides anything a case did not
    /// mean to test.
    static let inReach: Float = 40
    static let reach: Float = 141
    /// Never blocks, so a cadence case sees the attack it is asserting on.
    static let unblocking = CombatBehaviorSettings(blockChance: 0)
    /// Always blocks, so a block case does not depend on a draw.
    static let alwaysBlocking = CombatBehaviorSettings(blockChance: 1)

    static func machine(
        settings: CombatBehaviorSettings = CombatBehaviorSettings.standard
    ) -> CombatBehaviorMachine {
        CombatBehaviorMachine(settings: settings, seed: 1)
    }

    static func inputs(
        distance: Float = inReach,
        state: DetectionState = .detected,
        lastKnown: SIMD3<Float>? = SIMD3(0, 0, 0),
        healthFraction: Float = 1,
        isTargetAlive: Bool = true,
        isForced: Bool = false
    ) -> CombatBehaviorInputs {
        CombatBehaviorInputs(
            actorPosition: SIMD3(distance, 0, 0),
            targetPosition: SIMD3(0, 0, 0),
            awareness: CombatAwareness(state: state, lastKnownPosition: lastKnown),
            reach: reach,
            healthFraction: healthFraction,
            isTargetAlive: isTargetAlive,
            isForced: isForced
        )
    }

    /// Runs steps until `condition` holds or `limit` seconds have gone by,
    /// returning every step that came out.
    ///
    /// A condition rather than a duration wherever a case is about a
    /// *transition*: the exact step a phase changes on depends on how many
    /// steps the machine spent getting into it, and an assertion counted from
    /// the settings would be re-deriving the machine's own bookkeeping.
    @discardableResult
    static func run(
        _ machine: inout CombatBehaviorMachine,
        until condition: (CombatBehaviorMachine) -> Bool,
        limit: Float = 30,
        inputs: CombatBehaviorInputs
    ) -> [CombatBehaviorStep] {
        var steps: [CombatBehaviorStep] = []
        var elapsed: Float = 0
        while elapsed < limit, !condition(machine) {
            steps.append(machine.step(seconds: step, inputs: inputs))
            elapsed += step
        }
        return steps
    }

    /// Runs `seconds` of steps and returns every step that came out.
    @discardableResult
    static func run(
        _ machine: inout CombatBehaviorMachine,
        seconds: Float,
        inputs: CombatBehaviorInputs
    ) -> [CombatBehaviorStep] {
        var steps: [CombatBehaviorStep] = []
        var elapsed: Float = 0
        while elapsed < seconds {
            steps.append(machine.step(seconds: step, inputs: inputs))
            elapsed += step
        }
        return steps
    }
}
