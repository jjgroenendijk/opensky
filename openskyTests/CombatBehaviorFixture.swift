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
    /// Never casts inside weapon reach, so a melee case is not derailed by the
    /// cast roll (issue #473).
    static let neverCasting = CombatBehaviorSettings(blockChance: 0, castChance: 0)
    /// Always casts when it can, so a casting case does not depend on a draw.
    static let alwaysCasting = CombatBehaviorSettings(blockChance: 0, castChance: 1)

    /// A fire-and-forget spell that reaches across the room and costs little.
    static let fireball = CombatSpellOption(
        spell: .generated(101),
        cost: 20,
        range: 3000,
        chargeSeconds: 0.5
    )
    /// A costlier spell, so the "most expensive affordable option" rule has
    /// something to prefer.
    static let firestorm = CombatSpellOption(
        spell: .generated(102),
        cost: 80,
        range: 3000,
        chargeSeconds: 0.5
    )
    /// A maintained spell, which is held rather than let go the moment it has
    /// finished charging.
    static let flames = CombatSpellOption(
        spell: .generated(103),
        cost: 10,
        range: 600,
        chargeSeconds: 0,
        isConcentration: true
    )

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
        isForced: Bool = false,
        casting: CombatCastingProfile = .none
    ) -> CombatBehaviorInputs {
        CombatBehaviorInputs(
            actorPosition: SIMD3(distance, 0, 0),
            targetPosition: SIMD3(0, 0, 0),
            awareness: CombatAwareness(state: state, lastKnownPosition: lastKnown),
            reach: reach,
            healthFraction: healthFraction,
            isTargetAlive: isTargetAlive,
            isForced: isForced,
            casting: casting
        )
    }

    /// A caster with `magicka` to spend and `options` to spend it on.
    static func casting(
        magicka: Float,
        _ options: [CombatSpellOption]
    ) -> CombatCastingProfile {
        CombatCastingProfile(magicka: magicka, options: options)
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
