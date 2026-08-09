// The `Actor` native family (issue #375, roadmap item 15.8), invoked directly
// against a synthetic actor with a live actor-value runtime and a live ragdoll
// runtime behind it: one test per registered function plus its failure path,
// and the death chain the acceptance gate names.
//
// The session here is the real one — `PapyrusWorldStateBridge` over a real
// `WorldStateStore`, `ActorValueRuntime` and `RagdollRuntime` — rather than a
// fake bridge, because the thing worth testing is that a script's damage and a
// sword's damage reach the same store and the same death latch. Only the
// skeleton behind the ragdoll is faked, since decoding one needs game data.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct PapyrusNativeActorTests {
    private static let actorID: UInt32 = 0x0000_0A11
    private static let baseID: UInt32 = 0x0000_0B22
    private static let killerID: UInt32 = 0x0000_0C33
    /// Every actor in a session with no record indexes derives the fallback
    /// baseline, which is 100 of each (`vanillaPlayerStartingValues`).
    private static let fullHealth: Float = 100

    struct Fixture {
        let session: PapyrusWorldFixture.Session
        let registry: PapyrusNativeRegistry
        let receiver: PapyrusObjectHandle
        let key: ReferenceKey
        let ragdoll: RagdollRuntime
        let ragdollWorld: FakeRagdollWorld
        /// The live combat loop `StartCombat`, `StopCombat` and `IsInCombat`
        /// reach through (issue #424), over a recording world.
        let combat: CombatLoopRuntime
        let combatWorld: FakeCombatWorld
    }

    /// A scripted actor whose `OnDying` and `OnDeath` record a note, wired to a
    /// real value runtime and a real ragdoll runtime.
    static func fixture(
        weaponDrawState: WeaponDrawState? = nil
    ) throws -> Fixture {
        let entry = try PapyrusWorldFixture.actorEntry(
            objectID: actorID,
            base: baseID,
            scripts: [VMADFixture.Script("Bandit", properties: [])]
        )
        let session = PapyrusWorldFixture.session(
            objects: [PapyrusWorldFixture.eventScript("Bandit", events: [
                ("OnHit", PapyrusWorldFixture.probeBody(note: "onhit")),
                ("OnDying", PapyrusWorldFixture.probeBody(note: "ondying")),
                ("OnDeath", PapyrusWorldFixture.probeBody(note: "ondeath"))
            ])],
            entries: [entry]
        )
        PapyrusWorldFixture.drain(session.world)
        let ragdollWorld = FakeRagdollWorld()
        ragdollWorld.actor = ragdollActor(key: entry.key)
        // The death latch has to land in the same store `IsDead` reads back
        // through, or the two halves of this test would each be right about a
        // different world.
        ragdollWorld.store = session.worldState
        // The one thing the fake does not fake: the death's script events go to
        // the real world runtime, which is what the acceptance gate is about.
        ragdollWorld.deathEvents = { [weak world = session.world] key, killer in
            world?.queueActorDeath(actor: key, killer: killer) ?? 0
        }
        let ragdoll = RagdollRuntime(seam: ragdollWorld)
        let values = ActorValueRuntime(
            store: session.worldState, baselines: ActorValueBaselineResolver()
        )
        session.bridge.actorValueRuntime = { values }
        session.bridge.ragdollRuntime = { [weak ragdoll] in ragdoll }
        session.bridge.weaponDrawState = { _ in weaponDrawState }
        // A real combat loop over a recording world, so a scripted fight is the
        // same fight the player can walk into rather than a flag this test set.
        let combatWorld = FakeCombatWorld()
        combatWorld.actors = [CombatActorObservation(key: entry.key, feet: SIMD3(60, 0, 0))]
        combatWorld.awareness[entry.key] = .detected(at: SIMD3<Float>())
        let combat = CombatLoopRuntime(settings: .synthetic, world: combatWorld)
        session.bridge.combatRuntime = { [weak combat] in combat }
        return Fixture(
            session: session,
            registry: PapyrusWorldFixture.registry(for: session),
            receiver: session.world.objectHandle(for: entry.key),
            key: entry.key,
            ragdoll: ragdoll,
            ragdollWorld: ragdollWorld,
            combat: combat,
            combatWorld: combatWorld
        )
    }

    /// The one ragdoll a fake seam needs: no bodies, so nothing simulates, but
    /// enough for `noteZeroHealth` to accept the death.
    static func ragdollActor(key: ReferenceKey) -> RagdollActor {
        RagdollActor(
            key: key,
            cell: PapyrusWorldFixture.cell,
            reference: FormID(actorID),
            definition: RagdollDefinition(bones: [], joints: []),
            animatedBoneMatrices: [],
            actorToWorld: matrix_identity_float4x4
        )
    }

    @discardableResult
    func call(
        _ functionName: String,
        _ fixture: Fixture,
        receiver: PapyrusObjectHandle?,
        arguments: [PapyrusValue] = [],
        returnType: PapyrusType = .none
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "Actor", functionName, receiver: receiver,
            arguments: arguments, returnType: returnType
        ))
    }

    // MARK: - Reads

    @Test func theThreeValueReadsAgreeWithTheStore() throws {
        let fixture = try Self.fixture()
        call(
            "DamageActorValue", fixture, receiver: fixture.receiver,
            arguments: [.string("Health"), .float(25)]
        )
        #expect(call(
            "GetActorValue", fixture, receiver: fixture.receiver,
            arguments: [.string("Health")], returnType: .float
        ) == .returned(.float(75)))
        // The base value is the re-derived maximum and does not move with the
        // damage, which is the whole distinction the wiki draws.
        #expect(call(
            "GetBaseActorValue", fixture, receiver: fixture.receiver,
            arguments: [.string("Health")], returnType: .float
        ) == .returned(.float(Self.fullHealth)))
        #expect(call(
            "GetActorValuePercentage", fixture, receiver: fixture.receiver,
            arguments: [.string("health")], returnType: .float
        ) == .returned(.float(0.75)))
    }

    @Test func anActorValueWithNoStoreFailsAndIsTallied() throws {
        let fixture = try Self.fixture()
        let result = call(
            "GetActorValue", fixture, receiver: fixture.receiver,
            arguments: [.string("Sneak")], returnType: .float
        )
        #expect(PapyrusWorldFixture.isInvalidArguments(result))
    }

    @Test func aReceiverThatIsNotAnActorFails() throws {
        let fixture = try Self.fixture()
        let stranger = fixture.session.world.objectHandle(
            for: .plugin(name: PapyrusWorldFixture.pluginName, objectID: 0x0000_0DED)
        )
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "GetActorValue", fixture, receiver: stranger,
            arguments: [.string("Health")], returnType: .float
        )))
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "IsDead", fixture, receiver: nil, returnType: .boolean
        )))
    }

    // MARK: - Writes

    @Test func damageAndRestoreTakeTheMagnitudeAndClamp() throws {
        let fixture = try Self.fixture()
        // "Negative numbers will be converted to positive."
        call(
            "DamageActorValue", fixture, receiver: fixture.receiver,
            arguments: [.string("Magicka"), .float(-30)]
        )
        #expect(call(
            "GetActorValue", fixture, receiver: fixture.receiver,
            arguments: [.string("Magicka")], returnType: .float
        ) == .returned(.float(70)))
        // A restore past the maximum caps rather than overfilling.
        call(
            "RestoreActorValue", fixture, receiver: fixture.receiver,
            arguments: [.string("Magicka"), .float(500)]
        )
        #expect(call(
            "GetActorValue", fixture, receiver: fixture.receiver,
            arguments: [.string("Magicka")], returnType: .float
        ) == .returned(.float(Self.fullHealth)))
    }

    @Test func aNonFiniteAmountFailsRatherThanPoisoningTheStore() throws {
        let fixture = try Self.fixture()
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "DamageActorValue", fixture, receiver: fixture.receiver,
            arguments: [.string("Health"), .float(.nan)]
        )))
        #expect(call(
            "GetActorValue", fixture, receiver: fixture.receiver,
            arguments: [.string("Health")], returnType: .float
        ) == .returned(.float(Self.fullHealth)))
    }

    // MARK: - Death

    @Test func damageToZeroKillsAndFiresTheDeathEventsExactlyOnce() throws {
        let fixture = try Self.fixture()
        call(
            "DamageActorValue", fixture, receiver: fixture.receiver,
            arguments: [.string("Health"), .float(Self.fullHealth)]
        )
        #expect(call(
            "IsDead", fixture, receiver: fixture.receiver, returnType: .boolean
        ) == .returned(.boolean(true)))
        #expect(fixture.ragdoll.deathEventsQueued == 2)
        PapyrusWorldFixture.drain(fixture.session.world)
        #expect(fixture.session.dispatch.notes == ["ondying", "ondeath"])
        // A second fatal blow on a corpse latches nothing and raises nothing:
        // the "exactly once" guarantee is the latch's.
        call(
            "DamageActorValue", fixture, receiver: fixture.receiver,
            arguments: [.string("Health"), .float(Self.fullHealth)]
        )
        PapyrusWorldFixture.drain(fixture.session.world)
        #expect(fixture.session.dispatch.notes == ["ondying", "ondeath"])
        #expect(fixture.ragdoll.deathEventsQueued == 2)
    }

    @Test func killRoutesThroughTheSameDeathPathAndEmptiesHealth() throws {
        let fixture = try Self.fixture()
        let killer = fixture.session.world.objectHandle(
            for: .plugin(name: PapyrusWorldFixture.pluginName, objectID: Self.killerID)
        )
        call("Kill", fixture, receiver: fixture.receiver, arguments: [.object(killer)])
        // Health first, so `GetActorValue` and `IsDead` cannot disagree.
        #expect(call(
            "GetActorValue", fixture, receiver: fixture.receiver,
            arguments: [.string("Health")], returnType: .float
        ) == .returned(.float(0)))
        #expect(call(
            "IsDead", fixture, receiver: fixture.receiver, returnType: .boolean
        ) == .returned(.boolean(true)))
        // The same latch, the same events, and the same graph events the 15.6
        // sweep raises — this is one death path, not a second one.
        #expect(fixture.ragdollWorld.raised == RagdollGraphNames.deathEvents)
        #expect(fixture.ragdoll.deathEventsQueued == 2)
        PapyrusWorldFixture.drain(fixture.session.world)
        #expect(fixture.session.dispatch.notes == ["ondying", "ondeath"])
    }

    @Test func killWithNoKillerIsLegalAndPassesNone() throws {
        let fixture = try Self.fixture()
        call("Kill", fixture, receiver: fixture.receiver)
        #expect(call(
            "IsDead", fixture, receiver: fixture.receiver, returnType: .boolean
        ) == .returned(.boolean(true)))
        PapyrusWorldFixture.drain(fixture.session.world)
        #expect(fixture.session.dispatch.notes == ["ondying", "ondeath"])
    }

    // MARK: - Combat and weapon state

    @Test func isWeaponDrawnAnswersOnlyForAnObservedActor() throws {
        let unobserved = try Self.fixture()
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "IsWeaponDrawn", unobserved, receiver: unobserved.receiver,
            returnType: .boolean
        )))
        let drawn = try Self.fixture(weaponDrawState: .drawn)
        #expect(call(
            "IsWeaponDrawn", drawn, receiver: drawn.receiver, returnType: .boolean
        ) == .returned(.boolean(true)))
        let sheathed = try Self.fixture(weaponDrawState: .sheathed)
        #expect(call(
            "IsWeaponDrawn", sheathed, receiver: sheathed.receiver, returnType: .boolean
        ) == .returned(.boolean(false)))
    }

    // MARK: - OnHit

    @Test func aLandedBlowQueuesOnHitOnTheTargetsScripts() throws {
        let fixture = try Self.fixture()
        let queued = fixture.session.world.queueOnHit(ScriptHitEvent(
            target: fixture.key,
            aggressor: .player,
            source: FormID(0x0000_0E44),
            isBlocked: true
        ))
        #expect(queued == 1)
        PapyrusWorldFixture.drain(fixture.session.world)
        #expect(fixture.session.dispatch.notes == ["onhit"])
    }

    @Test func onHitOnAnUnscriptedReferenceQueuesNothing() throws {
        let fixture = try Self.fixture()
        let queued = fixture.session.world.queueOnHit(ScriptHitEvent(
            target: .plugin(name: PapyrusWorldFixture.pluginName, objectID: 0x0000_0DED),
            aggressor: .player
        ))
        #expect(queued == 0)
    }
}
