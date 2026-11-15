// One cape on one actor: the shape the cloth moves, the bone it hangs from, and the delta
// stream that carries the cloth to the draw (docs/engine/cape-cloth.md). The world steps it
// through `ClothCoordinator`; as a scene animation it only lives and unloads with the actor.

import Foundation
import Metal
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyPhysics
public import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkyRenderResources
public import OpenSkyWorldInterface
import simd
import Synchronization

nonisolated public final class ClothPlayback: RenderAnimation {
    /// The object the cloth starts on, matched without case.
    public static let shapeName = "VampLordCapeMesh"

    public let actor: FormID
    /// The bone the cape rides, from its `Prn` extra data.
    public let bone: String
    /// The cape mesh, whose draw reads `deltas`.
    public let mesh: RenderMesh
    public let deltas: FaceMorphBuffer
    /// The body capsule's radius and height in actor space, from the actor's bounds.
    public let body: (radius: Float, height: Float)
    private let rest: [SIMD3<Float>]
    private let triangles: [UInt16]
    private let cloth = Mutex<VerletCloth?>(nil)

    init(
        actor: FormID, bone: String, mesh: RenderMesh, deltas: FaceMorphBuffer,
        body: (radius: Float, height: Float)
    ) {
        self.actor = actor
        self.bone = bone
        self.mesh = mesh
        self.deltas = deltas
        self.body = body
        rest = mesh.restPositions()
        triangles = mesh.triangleIndices()
    }

    /// The cloth of the actor wearing `assembly`, or nil when no worn part is the
    /// `capeArmor` or its model has no cape shape. `body` is the actor's bounds.
    public static func make(
        actor: FormID,
        assembly: ActorAssembly<ActorRenderAsset>,
        capeArmor: FormID?
    ) -> ClothPlayback? {
        guard let capeArmor else { return nil }
        let cape = assembly.models.first { model in
            guard case let .body(part) = model.role else { return false }
            switch part.origin {
            case let .skin(armor), let .outfit(armor): return armor == capeArmor
            }
        }
        guard
            let cape,
            let mesh = cape.asset.model.meshes.first(where: {
                $0.name?.caseInsensitiveCompare(shapeName) == .orderedSame
            }),
            let bone = mesh.skinning?.boneNames.first,
            let deltas = attempt({
                try FaceMorphBuffer(device: mesh.vertexBuffer.device, simulating: mesh)
            })
        else { return nil }
        let bounds = assembly.models.filter { $0.path != cape.path }
            .compactMap(\.asset.bounds)
            .reduce(nil) { (sum: ModelBounds?, next) in sum.map { $0.union(next) } ?? next }
        return ClothPlayback(
            actor: actor, bone: bone, mesh: mesh, deltas: deltas,
            body: bodyCapsule(bounds: bounds)
        )
    }

    /// The character controller's radius, which is the same for every actor in OpenSky,
    /// and the height of the bounds. Wings make the bounds far wider than the body.
    static func bodyCapsule(bounds: ModelBounds?) -> (radius: Float, height: Float) {
        let controller = PlayerCapsule.standard
        guard let bounds else { return (controller.radius, controller.height) }
        return (controller.radius, bounds.max.z - bounds.min.z)
    }

    /// The draw's face morph entry, so the cape draws through the morphed pipeline.
    public var renderBinding: [ObjectIdentifier: FaceMorphBuffer] {
        [ObjectIdentifier(mesh): deltas]
    }

    /// One frame. `boneToActor` is the bone's pose in actor space; nil skips the frame.
    func step(
        seconds: Float, actorToWorld: float4x4, boneToActor: float4x4,
        capsules: [ClothCapsule]
    ) {
        let shapeToWorld = actorToWorld * boneToActor * mesh.localTransform
        let local: [SIMD3<Float>]? = cloth.withLock { state in
            guard var current = state else {
                state = VerletCloth(rest: rest, triangles: triangles, shapeToWorld: shapeToWorld)
                return nil
            }
            current.step(seconds: seconds, shapeToWorld: shapeToWorld, capsules: capsules)
            state = current
            return current.localPositions(shapeToWorld: shapeToWorld)
        }
        guard let local else { return }
        deltas.setPositionDeltas(zip(local, rest).map { $0 - $1 })
    }

    /// The body capsule in world space: vertical from the actor's feet, raised 50 units at
    /// the top on each refresh.
    func bodyCapsule(actorToWorld: float4x4, scale: Float) -> ClothCapsule {
        let origin = actorToWorld.columns.3
        let feet = SIMD3(origin.x, origin.y, origin.z)
        let radius = body.radius * scale
        let height = body.height * scale
        return ClothCapsule(
            start: feet + SIMD3(0, 0, radius),
            end: feet + SIMD3(0, 0, height - radius + 50),
            radius: radius
        )
    }

    public func update(at _: Float) -> Int {
        0
    }
}
