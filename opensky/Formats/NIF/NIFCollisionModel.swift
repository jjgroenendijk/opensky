// Engine-facing collision values produced from NIF bhk blocks. Disk refs,
// padding, MOPP bytecode, and compressed chunk storage do not escape this
// boundary; milestone 4.3 can consume shapes without knowing NIF layouts.
//
// Reference: NifTools nif.xml (bhkNiCollisionObject, HavokFilter,
// bhkRigidBodyCInfo2010, bhk shape hierarchy).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif-collision.md.

import Foundation
import simd

nonisolated struct NIFCollisionFilter: Equatable, Sendable {
    /// NifTools SkyrimLayer raw value.
    let layer: UInt8
    /// NifTools CollisionFilterFlags: biped part + MOPP/no-collision/link bits.
    let flags: UInt8
    let group: UInt16

    var isPlayerSolid: Bool {
        // SkyrimLayer 12 = trigger, 15 = non-collidable. Flag 0x40 is
        // CollisionFilterFlags.No Collision.
        layer != 12 && layer != 15 && flags & 0x40 == 0
    }

    /// SkyrimLayer 12 (`SKYL_TRIGGER`) specifically. Not the negation of
    /// `isPlayerSolid`: layer 15 and the `No Collision` flag also fail that
    /// test without naming a trigger.
    var isTriggerVolume: Bool {
        layer == 12
    }
}

/// Which collision-object class carried the body. Static world geometry hangs
/// off `bhkCollisionObject`; the per-bone bodies of a character skeleton hang
/// off `bhkBlendCollisionObject`, which inherits it and appends two blend-gain
/// floats this decoder does not read.
nonisolated enum NIFCollisionCarrier: String, Sendable {
    case collisionObject = "bhkCollisionObject"
    case blendCollisionObject = "bhkBlendCollisionObject"
}

nonisolated struct NIFCollisionBody {
    let targetBlock: Int32
    /// Name of the target `NiAVObject`. On a character skeleton this is the
    /// bone the body belongs to, which is the only mapping the file carries
    /// between ragdoll bodies and the animation skeleton.
    let targetName: String?
    /// Block index of the `bhkRigidBody`/`bhkRigidBodyT` itself, so a
    /// constraint's entity pointers can name the bodies they bind.
    let bodyBlock: Int
    let carrier: NIFCollisionCarrier
    let collisionObjectFlags: UInt16
    let worldFilter: NIFCollisionFilter
    let rigidBodyFilter: NIFCollisionFilter
    /// NifTools hkResponseType raw values from bhkEntity + rigid-body CInfo.
    let entityResponse: UInt8
    let rigidBodyResponse: UInt8
    /// Mass, inertia, damping, friction, and motion classification.
    let dynamics: NIFRigidBodyDynamics
    /// Joints this body names. A joint binds two bodies and both list it, so
    /// the same block appears twice in a model; `NIFCollisionModel.constraints`
    /// is the de-duplicated view.
    let constraints: [NIFCollisionConstraint]
    /// nif.xml `Body Flags`: bit 1 means the body responds to wind.
    let bodyFlags: UInt16
    /// Model-local target transform composed with bhkRigidBodyT transform.
    let transform: float4x4
    let shapes: [NIFCollisionShape]

    /// Raw `hkMotionType` byte. `dynamics.motionSystem` names it.
    var motionSystem: UInt8 {
        dynamics.rawMotionSystem
    }

    var isPlayerSolid: Bool {
        worldFilter.isPlayerSolid
            && rigidBodyFilter.isPlayerSolid
            && entityResponse == 1
            && rigidBodyResponse == 1
    }

    /// A body either of whose duplicate Havok filters names SkyrimLayer 12.
    /// Either filter is enough because vanilla trigger bodies are inconsistent
    /// about which of the two copies carries the layer. Such a body is never
    /// player-solid, so trigger routing and solid collision stay disjoint.
    var isTriggerVolume: Bool {
        worldFilter.isTriggerVolume || rigidBodyFilter.isTriggerVolume
    }
}

nonisolated struct NIFCollisionShape {
    /// Body-local wrapper/chunk transform. Translation is in engine units.
    let transform: float4x4
    let geometry: NIFCollisionGeometry
    /// NifTools `SkyrimHavokMaterial`: the hash of the surface's Creation Kit
    /// material name (issue #358). Nil where the block carries no material, and
    /// left raw here because a NIF has no way to resolve it — turning it into a
    /// MATT record needs the plugin, which is `MaterialTypeIndex`'s job.
    ///
    /// One shape carries one material. Where a block stores several — a
    /// compressed mesh's chunks, a packed strip shape's sub-shapes — the
    /// decoder emits one shape per material rather than a per-triangle table,
    /// because those blocks already partition their geometry that way.
    let material: UInt32?

    init(
        transform: float4x4,
        geometry: NIFCollisionGeometry,
        material: UInt32? = nil
    ) {
        self.transform = transform
        self.geometry = geometry
        self.material = material
    }
}

nonisolated enum NIFCollisionGeometry {
    /// Vertices are engine units; indices are validated triangle triples.
    case triangleSoup(vertices: [SIMD3<Float>], indices: [UInt32])
    /// Original convex points + derived hull connectivity. NIF stores points
    /// and plane normals without triangle faces; faces are clean engine data.
    case convexVertices(vertices: [SIMD3<Float>], hullIndices: [UInt32])
    case box(halfExtents: SIMD3<Float>)
    case sphere(radius: Float)
    case capsule(first: SIMD3<Float>, second: SIMD3<Float>, radius: Float)
}

nonisolated struct NIFCollisionFailure: Equatable, Sendable {
    let block: Int
    let message: String
}

nonisolated struct NIFCollisionModel {
    /// 64 Skyrim units/yard converted to units/metre. Community constant;
    /// verified against vanilla Whiterun render/collision bounds in 4.2 probe.
    static let havokToEngineScale: Float = 69.99125

    let bodies: [NIFCollisionBody]
    /// Reachable shape/data variants omitted from output, grouped by block type.
    let unsupportedReachableBlocks: [String: Int]
    /// Per-root decode failures; other roots remain available.
    let decodeFailures: [NIFCollisionFailure]

    var shapeCount: Int {
        bodies.reduce(0) { $0 + $1.shapes.count }
    }

    var triangleCount: Int {
        bodies.reduce(0) { total, body in
            total + body.shapes.reduce(0) { shapeTotal, shape in
                guard case let .triangleSoup(_, indices) = shape.geometry else {
                    return shapeTotal
                }
                return shapeTotal + indices.count / 3
            }
        }
    }

    /// Havok material value -> how many decoded shapes name it. The probe's
    /// evidence that meshes carry materials at all, and that the values they
    /// carry are ones a MATT hashes to.
    var shapeMaterials: [UInt32: Int] {
        bodies.reduce(into: [:]) { counts, body in
            for shape in body.shapes {
                guard let material = shape.material else { continue }
                counts[material, default: 0] += 1
            }
        }
    }

    var filteredBodyCount: Int {
        bodies.count(where: { !$0.isPlayerSolid })
    }

    /// Every joint in the model, once. A joint binds two bodies and both of
    /// them list it, so the per-body arrays double-count.
    var constraints: [NIFCollisionConstraint] {
        var seen: Set<Int> = []
        return bodies.flatMap(\.constraints).filter { seen.insert($0.block).inserted }
    }

    /// Rigid-body block index -> the name of the scene object it hangs off.
    /// On a character skeleton that is the bone name.
    var bodyNamesByBlock: [Int: String] {
        bodies.reduce(into: [:]) { names, body in
            names[body.bodyBlock] = body.targetName
        }
    }

    /// The two bone names a joint binds, nil where the end points outside the
    /// decoded bodies or at an unnamed node.
    func boneNames(
        of constraint: NIFCollisionConstraint
    ) -> (a: String?, b: String?) {
        let names = bodyNamesByBlock
        return (names[Int(constraint.entityA)], names[Int(constraint.entityB)])
    }

    /// Model-space AABB after composing scene-target, rigid-body, wrapper,
    /// and chunk transforms. Primitive bounds are exact before rotation and
    /// conservative after the final affine transform.
    var bounds: ModelBounds? {
        var result: ModelBounds?
        for body in bodies {
            for shape in body.shapes {
                guard let local = Self.bounds(of: shape.geometry) else { continue }
                let transformed = local.transformed(by: body.transform * shape.transform)
                result = result.map { $0.union(transformed) } ?? transformed
            }
        }
        return result
    }

    private static func bounds(of geometry: NIFCollisionGeometry) -> ModelBounds? {
        switch geometry {
        case let .triangleSoup(vertices, _), let .convexVertices(vertices, _):
            return ModelBounds.containing(vertices)
        case let .box(halfExtents):
            return ModelBounds(min: -halfExtents, max: halfExtents)
        case let .sphere(radius):
            return ModelBounds(
                min: SIMD3(repeating: -radius),
                max: SIMD3(repeating: radius)
            )
        case let .capsule(first, second, radius):
            let extent = SIMD3<Float>(repeating: radius)
            return ModelBounds(
                min: simd_min(first, second) - extent,
                max: simd_max(first, second) + extent
            )
        }
    }
}
