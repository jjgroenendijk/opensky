// The shell of the actor-value domain: owns the runtime, steps regeneration,
// and runs the Combat panel's actor-value controls. The rules live in
// `ActorValueRuntime`. See docs/engine/coordinators.md.

import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// Owns the actor-value runtime and reads the world through `ActorValueWorld`.
/// Without game data the runtime stays nil, and the panel reports itself
/// unavailable rather than showing a convincing zero.
@MainActor
public final class ActorValueCoordinator {
    /// Nil until `wire`.
    public private(set) var runtime: ActorValueRuntime?
    /// Which target the panel's controls act on.
    public var target = ActorValueTargetSelector.player
    /// Which actor value they act on, by vanilla table index. Health first.
    public var selection: Int32 = 24
    public internal(set) var lastActionText = "No actor-value action yet."
    /// Kept here, not in the runtime: the runtime is a struct over a shared
    /// store, and a per-copy accumulator would split the simulation.
    private var regenAccumulator: Double = 0
    /// Regeneration walks holders in key order; this keeps that order between frames.
    private var holderOrder = ReferenceKeyOrder()

    let store: WorldStateStore
    weak var world: (any ActorValueWorld)?

    public init(store: WorldStateStore) {
        self.store = store
    }

    public func attach(world: any ActorValueWorld) {
        self.world = world
    }

    public func wire(baselines: ActorValueBaselineResolver) {
        runtime = ActorValueRuntime(store: store, baselines: baselines)
    }

    /// Runs whole regeneration steps for the delta this frame simulated.
    ///
    /// A caster does not regenerate: "Magicka will not regenerate while you
    /// are casting a spell" (<https://en.uesp.net/wiki/Skyrim:Magicka>). NPCs
    /// follow the same rule; docs/engine/spellcasting.md records the deviation.
    public func advance(delta: Float) {
        guard let runtime, let world else { return }
        let holders = holderOrder.sorted(world.regeneratingHolders(), by: \.key)
            .filter { !world.isCasting($0.key) }
        runtime.advance(delta: delta, accumulator: &regenAccumulator, over: holders)
    }

    /// The NPC_ base FormID, which is what the user types into the record dump.
    public static func name(of holder: ActorValueHolder) -> String {
        switch holder.subject {
        case .player: "Player"
        case let .actor(base): "\(holder.key.description) (base \(base))"
        case .generated: holder.key.description
        }
    }
}
