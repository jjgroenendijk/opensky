// The `Actor` combat natives and the `IsInCombat` reading they change, over
// the same synthetic actor as `PapyrusNativeActorTests` plus a real combat
// loop. A separate file only because of the lint type cap.

@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
import OpenSkyCombatTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyScripting
@testable import OpenSkyScriptingInterface
import OpenSkyScriptingTesting
import simd
import Testing

@MainActor
extension PapyrusNativeActorTests {
    /// `IsInCombat` reads what the actor is *doing*, not what it feels: an
    /// actor made hostile without a fight running answers false, and only
    /// `StartCombat` (or perceiving the player) turns it true.
    @Test func isInCombatReadsTheFightAndNotACorpse() throws {
        let fixture = try Self.fixture()
        #expect(call(
            "IsInCombat", fixture, receiver: fixture.receiver, returnType: .boolean
        ) == .returned(.boolean(false)))

        fixture.combat.startCombat(fixture.key, with: .player)
        fixture.combat.advance(by: CombatLoopRuntime.fixedStepSeconds * 2)
        #expect(call(
            "IsInCombat", fixture, receiver: fixture.receiver, returnType: .boolean
        ) == .returned(.boolean(true)))

        call("Kill", fixture, receiver: fixture.receiver)
        fixture.combatWorld.kill(fixture.key)
        fixture.combat.advance(by: CombatLoopRuntime.fixedStepSeconds * 2)
        #expect(call(
            "IsInCombat", fixture, receiver: fixture.receiver, returnType: .boolean
        ) == .returned(.boolean(false)))
    }

    /// `StartCombat` writes hostility on its way through, so a scripted fight
    /// is saved exactly as one the player started.
    @Test func startCombatEngagesTheActorAgainstThePlayerAndWritesHostility() throws {
        let fixture = try Self.fixture()
        let player = fixture.session.world.objectHandle(for: .player)

        call("StartCombat", fixture, receiver: fixture.receiver, arguments: [.object(player)])
        fixture.combat.advance(by: CombatLoopRuntime.fixedStepSeconds * 2)

        #expect(fixture.combatWorld.hostility[fixture.key] == .hostile)
        #expect(fixture.combat.state.isPlayerInCombat)
    }

    /// A target this engine simulates no fight against is a tallied failure
    /// rather than a fight that silently does not happen.
    @Test func startCombatRefusesATargetOtherThanThePlayer() throws {
        let fixture = try Self.fixture()
        let other = fixture.session.world.objectHandle(for: fixture.key)

        let outcome = call(
            "StartCombat", fixture, receiver: fixture.receiver, arguments: [.object(other)]
        )

        #expect(PapyrusWorldFixture.isInvalidArguments(outcome))
        #expect(fixture.combatWorld.hostility.isEmpty)
    }

    /// `StopCombat` ends the fight and leaves the actor's stored hostility
    /// alone: the wiki's `StopCombat` stops the fighting, not the feeling.
    @Test func stopCombatEndsTheFightAndLeavesHostilityAlone() throws {
        let fixture = try Self.fixture()
        fixture.combat.startCombat(fixture.key, with: .player)
        fixture.combat.advance(by: CombatLoopRuntime.fixedStepSeconds * 2)

        call("StopCombat", fixture, receiver: fixture.receiver)

        // Read before the next step, deliberately. `StopCombat` stops the
        // fighting and leaves the actor hostile and standing in front of the
        // player, so the very next step perceives them and starts it again —
        // the same reason a vanilla script that means it also changes the
        // relationship. Stated in docs/engine/combat.md.
        #expect(fixture.combat.phase(of: fixture.key)?.isEngaged != true)
        #expect(fixture.combatWorld.hostility[fixture.key] == .hostile)
        #expect(fixture.combatWorld.packageResumes.contains(fixture.key))
    }
}
