// Shared setup for the two combat-loop suites (issue #424).
//
// One fight is more behaviour than the strict lint type cap allows in one type,
// so the runtime's cases live in two files — the entry-and-attack half and the
// breaking-off half — and the session both build lives here.

@testable import opensky
import simd

@MainActor
enum CombatLoopFixture {
    static let opponent = ReferenceKey.generated(1)
    static let second = ReferenceKey.generated(2)
    /// Inside unarmed reach — `fCombatDistance` is 141 in the synthetic
    /// settings and the machine closes to within 24 of that.
    static let closeFeet = SIMD3<Float>(60, 0, 0)
    /// Well outside it, so the actor has to walk.
    static let farFeet = SIMD3<Float>(4000, 0, 0)

    /// One full attack cycle, plus a step of slack.
    static let cycleSeconds = CombatBehaviorSettings.standard.attackIntervalSeconds
        + CombatBehaviorSettings.standard.windupSeconds
        + CombatBehaviorSettings.standard.recoverySeconds
        + CombatLoopRuntime.fixedStepSeconds

    /// A runtime over one opponent, with the block roll pinned off so a case
    /// that asserts on an attack is not waiting out a guard it did not ask for.
    static func session(
        weaponDamage: Float = 12,
        feet: SIMD3<Float> = closeFeet,
        blockChance: Float = 0
    ) -> (runtime: CombatLoopRuntime, world: FakeCombatWorld) {
        let world = FakeCombatWorld()
        world.actors = [CombatActorObservation(key: opponent, feet: feet, name: "Opponent")]
        world.weapons[opponent] = MeleeWeaponProfile(damage: weaponDamage, reach: 1)
        let runtime = CombatLoopRuntime(settings: .synthetic, world: world)
        runtime.behaviorSettings = CombatBehaviorSettings(blockChance: blockChance)
        return (runtime, world)
    }

    /// Makes `key` hostile and lets it perceive the player, which is the whole
    /// of 16.7's combat entry: no spawn, no designation, no clock.
    static func engage(
        _ runtime: CombatLoopRuntime,
        _ world: FakeCombatWorld,
        _ key: ReferenceKey = opponent
    ) {
        world.awareness[key] = .detected(at: world.player.feet)
        runtime.setHostility(.hostile, on: key)
    }

    /// Advances `runtime` for `seconds`, one fixed step per call.
    ///
    /// One step per call rather than one long delta, because `advance(by:)`
    /// deliberately caps a single call at `maximumStepsPerAdvance` — that is the
    /// stall guard, and driving a two-second fight through it would silently
    /// simulate an eighth of a second.
    static func run(_ runtime: CombatLoopRuntime, seconds: Float) {
        var elapsed: Float = 0
        while elapsed < seconds {
            runtime.advance(by: CombatLoopRuntime.fixedStepSeconds)
            elapsed += CombatLoopRuntime.fixedStepSeconds
        }
    }
}
