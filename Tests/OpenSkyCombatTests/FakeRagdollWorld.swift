@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyWorldState
import PhysicsTesting
import simd

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
