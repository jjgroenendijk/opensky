// Death activation (issue #197, item 15.6): the runtime driven against a fake
// world, with no renderer, no window and no game data.
//
// The fake records which events were raised and answers whether a graph took
// them, which is the one bit that decides whether a death waits for the graph's
// hand-off or falls back to an immediate one.

@testable import opensky
import simd
import Testing

@MainActor
final class FakeRagdollWorld: RagdollWorldSeam {
    var actor: RagdollActor?
    /// Which event names a graph is pretending to declare. Empty means no graph
    /// is attached, which is what routes a death down the fallback.
    var declaredEvents: Set<String> = []
    private(set) var raised: [String] = []
    private(set) var writes: [(key: ReferenceKey, state: ActorDeathState)] = []
    var states: [ReferenceKey: ActorDeathState] = [:]
    var ragdollStepWorld = DynamicStepWorld()

    func ragdollActor(for key: ReferenceKey) -> RagdollActor? {
        actor?.key == key ? actor : nil
    }

    @discardableResult
    func raiseRagdollEvent(_ name: String, on key: ReferenceKey) -> Bool {
        raised.append(name)
        return declaredEvents.contains(name)
    }

    /// A real store to mirror writes into, for a test whose *other* half reads
    /// the death latch back through `WorldStateStore` — the Papyrus `IsDead`
    /// native, above all. Nil for the ragdoll tests themselves, which only ever
    /// read `states` back.
    var store: WorldStateStore?

    func writeDeathState(
        _ state: ActorDeathState, for key: ReferenceKey, in cell: CellSceneLocation
    ) {
        states[key] = state
        writes.append((key: key, state: state))
        store?.set(state, for: key, in: cell)
    }

    func deathState(of key: ReferenceKey) -> ActorDeathState? {
        states[key]
    }

    /// Where a death's script events go (issue #375). Nil is the seam's own
    /// default — a world with no VM — and a test that cares about the events
    /// installs a closure into the real `PapyrusWorldRuntime`.
    var deathEvents: ((ReferenceKey, ReferenceKey?) -> Int)?

    @discardableResult
    func queueActorDeathEvents(for key: ReferenceKey, killer: ReferenceKey?) -> Int {
        deathEvents?(key, killer) ?? 0
    }
}

@MainActor
struct RagdollRuntimeTests {
    private static let key = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x1234)
    private static let cell = CellSceneLocation.interior(FormID(0x20))

    /// A death whose graph takes the events waits for the hand-off: the actor is
    /// recorded dead and no bodies exist yet.
    @Test
    func aGraphDrivenDeathWaitsForTheHandOff() {
        let (runtime, world) = Self.session(declaring: RagdollGraphNames.deathEvents)
        #expect(runtime.noteZeroHealth(of: Self.key))
        #expect(world.raised == RagdollGraphNames.deathEvents)
        #expect(runtime.isDead(Self.key))
        #expect(runtime.world.ragdollCount == 0)
        #expect(runtime.pendingHandOffs.contains(Self.key))
        #expect(runtime.graphDrivenDeathCount == 1)
        #expect(runtime.fallbackDeathCount == 0)
    }

    /// The hand-off event spawns the bodies.
    @Test
    func theHandOffEventSpawnsTheBodies() {
        let (runtime, world) = Self.session(declaring: RagdollGraphNames.deathEvents)
        runtime.noteZeroHealth(of: Self.key)
        #expect(world.raised == RagdollGraphNames.deathEvents)
        #expect(runtime.handleGraphEvents([RagdollGraphNames.addRagdollToWorld], on: Self.key))
        #expect(runtime.world.ragdollCount == 1)
        #expect(runtime.pendingHandOffs.isEmpty)
        let instance = runtime.world.instance(for: Self.key)
        #expect(instance?.bodies.count == 3)
        #expect(instance?.blendDuration == runtime.blendDuration)
    }

    /// `RagdollInstant` skips the blend, which is the difference between the two
    /// hand-off spellings.
    @Test
    func theInstantHandOffSkipsTheBlend() {
        let (runtime, world) = Self.session(declaring: RagdollGraphNames.deathEvents)
        runtime.noteZeroHealth(of: Self.key)
        runtime.handleGraphEvents([RagdollGraphNames.ragdollInstant], on: Self.key)
        #expect(world.states[Self.key]?.isDead == true)
        #expect(runtime.world.instance(for: Self.key)?.blendDuration == 0)
        #expect(runtime.world.instance(for: Self.key)?.simulationWeight == 1)
    }

    /// An unrelated event is not a hand-off.
    @Test
    func anUnrelatedEventIsNotAHandOff() {
        let (runtime, world) = Self.session(declaring: RagdollGraphNames.deathEvents)
        runtime.noteZeroHealth(of: Self.key)
        #expect(world.states[Self.key]?.isDead == true)
        #expect(!runtime.handleGraphEvents(["FootLeft", "attackStart"], on: Self.key))
        #expect(runtime.world.ragdollCount == 0)
    }

    /// An actor with no graph attached still falls: the death events go
    /// unclaimed, so the runtime hands off itself and says that it did.
    @Test
    func aGraphlessDeathFallsBackToAnImmediateHandOff() {
        let (runtime, world) = Self.session(declaring: [])
        #expect(runtime.noteZeroHealth(of: Self.key))
        #expect(world.raised == RagdollGraphNames.deathEvents)
        #expect(runtime.world.ragdollCount == 1)
        #expect(runtime.fallbackDeathCount == 1)
        #expect(runtime.graphDrivenDeathCount == 0)
        #expect(runtime.pendingHandOffs.isEmpty)
    }

    /// Killing an already-dead actor does nothing, so a per-frame sweep over
    /// every resident actor is safe to run without tracking edges.
    @Test
    func killingATwiceDeadActorIsANoOp() {
        let (runtime, world) = Self.session(declaring: [])
        #expect(runtime.noteZeroHealth(of: Self.key))
        let raisedOnce = world.raised.count
        #expect(!runtime.noteZeroHealth(of: Self.key))
        #expect(world.raised.count == raisedOnce)
        #expect(runtime.world.ragdollCount == 1)
    }

    /// The dev trigger kills and hands off in one call, which is what the panel
    /// button does.
    @Test
    func theDevTriggerKillsAndHandsOff() {
        let (runtime, world) = Self.session(declaring: RagdollGraphNames.deathEvents)
        #expect(runtime.trigger(Self.key))
        #expect(world.states[Self.key]?.isDead == true)
        #expect(runtime.isDead(Self.key))
        #expect(runtime.world.ragdollCount == 1)
    }

    /// A corpse that settles writes its resting root transform into the death
    /// component, which is what a save records.
    @Test
    func aSettledCorpseRecordsItsRestingTransform() {
        let (runtime, world) = Self.session(declaring: [])
        world.ragdollStepWorld = RagdollFixture.floorWorld()
        runtime.noteZeroHealth(of: Self.key)
        for _ in 0 ..< 400 {
            runtime.advance(by: WalkController.fixedTimeStep * 8)
        }
        #expect(runtime.world.instance(for: Self.key)?.isSettled == true)
        #expect(world.states[Self.key]?.restingTransform != nil)
    }

    /// A dead actor opens as a corpse, and searching it is recorded.
    @Test
    func aCorpseRecordsThatItWasLooted() {
        let (runtime, world) = Self.session(declaring: [])
        #expect(!runtime.opensAsCorpse(Self.key))
        runtime.noteZeroHealth(of: Self.key)
        #expect(runtime.opensAsCorpse(Self.key))
        #expect(world.states[Self.key]?.wasLooted == false)
        runtime.noteLooted(Self.key)
        #expect(world.states[Self.key]?.wasLooted == true)
        // A second search writes nothing further.
        let writeCount = world.writes.count
        runtime.noteLooted(Self.key)
        #expect(world.writes.count == writeCount)
    }

    /// A living actor cannot be looted as a corpse.
    @Test
    func aLivingActorIsNotLootable() {
        let (runtime, world) = Self.session(declaring: [])
        runtime.noteLooted(Self.key)
        #expect(world.writes.isEmpty)
    }

    /// A reset drops the live ragdolls but not the deaths, which belong to the
    /// store.
    @Test
    func resetKeepsTheDeathAndDropsTheBodies() {
        let (runtime, world) = Self.session(declaring: [])
        runtime.noteZeroHealth(of: Self.key)
        runtime.reset()
        #expect(runtime.world.ragdollCount == 0)
        #expect(world.states[Self.key]?.isDead == true)
    }

    /// An actor the session cannot resolve a skeleton for is not killed at all,
    /// rather than being recorded dead with no way to fall.
    @Test
    func anUnresolvableActorIsNotKilled() {
        let (runtime, world) = Self.session(declaring: [])
        world.actor = nil
        #expect(!runtime.noteZeroHealth(of: Self.key))
        #expect(world.states.isEmpty)
    }

    // MARK: - Fixture

    /// A runtime and the fake it resolves against.
    ///
    /// Both halves have to be bound by the caller. `RagdollRuntime` holds its
    /// seam weakly — the session owns the world, not the other way round, the
    /// same as `MeleeCombatRuntime` — so a test that discards the fake is
    /// testing a runtime with no world attached.
    private static func session(
        declaring events: [String]
    ) -> (RagdollRuntime, FakeRagdollWorld) {
        let world = FakeRagdollWorld()
        world.declaredEvents = Set(events)
        world.actor = RagdollActor(
            key: key,
            cell: cell,
            reference: FormID(0x30),
            definition: RagdollFixture.limb().definition,
            animatedBoneMatrices: (0 ..< 3).map {
                MatrixMath.translation(
                    SIMD3(Float($0) * RagdollFixture.boneHalfLength * 2, 0, 120)
                )
            },
            actorToWorld: matrix_identity_float4x4
        )
        return (RagdollRuntime(seam: world), world)
    }
}
