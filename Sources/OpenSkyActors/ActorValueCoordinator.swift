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
    public internal(set) var lastAction = ActorValueActionOutcome.idle
    /// Kept here, not in the runtime: the runtime is a struct over a shared
    /// store, and a per-copy accumulator would split the simulation.
    private var regenAccumulator: Double = 0
    /// Regeneration walks holders in key order; this keeps that order between frames.
    private var holderOrder = ReferenceKeyOrder()
    /// What sprinting costs; `wire` sets it from the load order.
    public private(set) var stamina = StaminaSettings.vanilla

    let store: WorldStateStore
    weak var world: (any ActorValueWorld)?

    public init(store: WorldStateStore) {
        self.store = store
    }

    public func attach(world: any ActorValueWorld) {
        self.world = world
    }

    public func wire(
        baselines: ActorValueBaselineResolver,
        regeneration: RegenerationSettings = .vanilla,
        stamina: StaminaSettings = .vanilla
    ) {
        self.stamina = stamina
        runtime = ActorValueRuntime(
            store: store, baselines: baselines, regeneration: regeneration
        )
    }

    /// Runs whole regeneration steps for the delta this frame simulated. Combat
    /// slows each value, and casting stops magicka (`RegenerationSettings`).
    public func advance(delta: Float) {
        guard let runtime, let world else { return }
        drainSprint(delta: delta, runtime: runtime, world: world)
        let holders = holderOrder.sorted(world.regeneratingHolders(), by: \.key)
        runtime.advance(delta: delta, accumulator: &regenAccumulator, over: holders) {
            RegenerationSituation(
                isInCombat: world.isInCombat($0.key), isCasting: world.isCasting($0.key)
            )
        }
    }

    /// Sprinting drains the player's stamina, and an empty bar stops the sprint.
    private func drainSprint(delta: Float, runtime: ActorValueRuntime, world: any ActorValueWorld) {
        guard delta.isFinite, delta > 0 else { return }
        if let worn = world.playerSprintLoad() {
            runtime.damage(.stamina, by: stamina.sprintDrain(wornWeight: worn) * delta, on: .player)
        }
        world.setPlayerSprintAllowed(runtime.current(of: .player).stamina > 0)
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
