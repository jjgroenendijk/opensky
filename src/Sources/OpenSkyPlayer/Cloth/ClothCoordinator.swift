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

/// Why a cape skipped its step: what the world could not give for its actor.
public enum ClothFrameMiss: String, Sendable {
    case noPlayerBody
    case noPlayerPose
    case actorNotLoaded
    case actorNotPosed
    case boneNotPosed
}

/// What `ClothCoordinator` reads from the running world.
public protocol ClothWorld: AnyObject {
    /// Every loaded cloth, the player's included.
    var clothPlaybacks: [ClothPlayback] { get }
    /// Nil when the actor is not posed this frame, which skips its cloth.
    func clothFrame(for cloth: ClothPlayback) -> ClothActorFrame?
    /// Why `clothFrame(for:)` gives nil now; nil when it gives a frame.
    func clothFrameMiss(for cloth: ClothPlayback) -> ClothFrameMiss?
}

extension ClothWorld {
    public func clothFrameMiss(for _: ClothPlayback) -> ClothFrameMiss? {
        nil
    }
}

/// One loaded cape in `state cloth`.
public struct ClothCapeReadout: Sendable {
    public var actor: FormID
    /// The bone the cape hangs from.
    public var bone: String
    /// Whether the last tick stepped it, and else why not.
    public var stepped: Bool
    public var miss: ClothFrameMiss?

    public init(actor: FormID, bone: String, stepped: Bool = false, miss: ClothFrameMiss? = nil) {
        self.actor = actor
        self.bone = bone
        self.stepped = stepped
        self.miss = miss
    }
}

/// What `state cloth` shows.
public struct ClothReadout: Sendable {
    public var isEnabled: Bool
    public var steppedCount: Int
    public var capes: [ClothCapeReadout]

    public init(isEnabled: Bool, steppedCount: Int, capes: [ClothCapeReadout]) {
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
    private var lastStepped: Set<ObjectIdentifier> = []

    public var readout: ClothReadout {
        let capes = (world?.clothPlaybacks ?? []).map { cloth in
            let stepped = lastStepped.contains(ObjectIdentifier(cloth))
            return ClothCapeReadout(
                actor: cloth.actor, bone: cloth.bone, stepped: stepped,
                miss: stepped ? nil : world?.clothFrameMiss(for: cloth)
            )
        }
        return ClothReadout(isEnabled: isEnabled, steppedCount: lastSteppedCount, capes: capes)
    }

    public init(world: any ClothWorld) {
        self.world = world
    }

    public func tick(deltaTime: Float) {
        lastSteppedCount = 0
        lastStepped = []
        guard isEnabled, deltaTime > 0, let world else { return }
        for cloth in world.clothPlaybacks {
            guard let frame = world.clothFrame(for: cloth) else { continue }
            let body = cloth.bodyCapsule(actorToWorld: frame.actorToWorld, scale: frame.scale)
            cloth.step(
                seconds: deltaTime, actorToWorld: frame.actorToWorld,
                boneToActor: frame.boneToActor, capsules: [body] + frame.calves
            )
            lastSteppedCount += 1
            lastStepped.insert(ObjectIdentifier(cloth))
        }
    }
}
