@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyWorldState
import simd

@MainActor
public final class FakeRagdollWorld: RagdollWorldSeam {
    public var actor: RagdollActor?
    /// Which event names a graph is pretending to declare. Empty means no graph
    /// is attached, which is what routes a death down the fallback.
    public var declaredEvents: Set<String> = []
    public private(set) var raised: [String] = []
    public private(set) var writes: [(key: ReferenceKey, state: ActorDeathState)] = []
    public var states: [ReferenceKey: ActorDeathState] = [:]
    public var ragdollStepWorld = DynamicStepWorld()

    public init() {}

    public func ragdollActor(for key: ReferenceKey) -> RagdollActor? {
        actor?.key == key ? actor : nil
    }

    @discardableResult
    public func raiseRagdollEvent(_ name: String, on key: ReferenceKey) -> Bool {
        raised.append(name)
        return declaredEvents.contains(name)
    }

    /// A real store to mirror writes into, for a test whose *other* half reads
    /// the death latch back through `WorldStateStore` — the Papyrus `IsDead`
    /// native, above all. Nil for the ragdoll tests themselves, which only ever
    /// read `states` back.
    public var store: WorldStateStore?

    public func writeDeathState(
        _ state: ActorDeathState, for key: ReferenceKey, in cell: CellSceneLocation
    ) {
        states[key] = state
        writes.append((key: key, state: state))
        store?.set(state, for: key, in: cell)
    }

    public func deathState(of key: ReferenceKey) -> ActorDeathState? {
        states[key]
    }

    /// Where a death's script events go. Nil is the seam's own
    /// default — a world with no VM — and a test that cares about the events
    /// installs a closure into the real `PapyrusWorldRuntime`.
    public var deathEvents: ((ReferenceKey, ReferenceKey?) -> Int)?

    @discardableResult
    public func queueActorDeathEvents(for key: ReferenceKey, killer: ReferenceKey?) -> Int {
        deathEvents?(key, killer) ?? 0
    }
}
