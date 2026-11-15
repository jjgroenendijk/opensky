// Steps every loaded cape once per world tick, after the actor graphs, so the pins follow
// this frame's pose (docs/engine/cape-cloth.md).

public import OpenSkyFormatsESM
public import OpenSkyPhysics
public import simd

/// Where one cloth's actor stands and how it is posed this frame.
public struct ClothActorFrame {
    public var actorToWorld: float4x4
    public var scale: Float
    /// The cape's bone in actor space.
    public var boneToActor: float4x4
    /// The calf capsules in world space; empty when the actor's ragdoll has none.
    public var calves: [ClothCapsule]

    public init(
        actorToWorld: float4x4, scale: Float, boneToActor: float4x4, calves: [ClothCapsule] = []
    ) {
        self.actorToWorld = actorToWorld
        self.scale = scale
        self.boneToActor = boneToActor
        self.calves = calves
    }
}

/// What `ClothCoordinator` reads from the running world.
public protocol ClothWorld: AnyObject {
    /// Every loaded cloth, the player's included.
    var clothPlaybacks: [ClothPlayback] { get }
    /// Nil when the actor is not posed this frame, which skips its cloth.
    func clothFrame(for cloth: ClothPlayback) -> ClothActorFrame?
}

/// What `state cloth` shows.
public struct ClothReadout: Sendable {
    public var isEnabled: Bool
    public var steppedCount: Int
    /// Each loaded cape's actor and the bone it hangs from.
    public var capes: [(actor: FormID, bone: String)]

    public init(isEnabled: Bool, steppedCount: Int, capes: [(actor: FormID, bone: String)]) {
        self.isEnabled = isEnabled
        self.steppedCount = steppedCount
        self.capes = capes
    }
}

public final class ClothCoordinator {
    public private(set) weak var world: (any ClothWorld)?
    /// Off holds every cape where it last was.
    public var isEnabled = true
    /// Cloths stepped by the last tick, for the readout.
    public private(set) var lastSteppedCount = 0

    public var readout: ClothReadout {
        ClothReadout(
            isEnabled: isEnabled, steppedCount: lastSteppedCount,
            capes: (world?.clothPlaybacks ?? []).map { ($0.actor, $0.bone) }
        )
    }

    public init(world: any ClothWorld) {
        self.world = world
    }

    public func tick(deltaTime: Float) {
        lastSteppedCount = 0
        guard isEnabled, deltaTime > 0, let world else { return }
        for cloth in world.clothPlaybacks {
            guard let frame = world.clothFrame(for: cloth) else { continue }
            let body = cloth.bodyCapsule(actorToWorld: frame.actorToWorld, scale: frame.scale)
            cloth.step(
                seconds: deltaTime, actorToWorld: frame.actorToWorld,
                boneToActor: frame.boneToActor, capsules: [body] + frame.calves
            )
            lastSteppedCount += 1
        }
    }
}
