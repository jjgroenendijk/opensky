// Engine-facing collision values made from NIF bhk blocks. Disk refs, MOPP
// code, and compressed chunks stay behind this boundary.
// Layout and sources: docs/formats/nif-collision.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct NIFCollisionFilter: Equatable, Sendable {
    /// NifTools SkyrimLayer raw value.
    public let layer: UInt8
    /// NifTools CollisionFilterFlags: biped part + MOPP/no-collision/link bits.
    public let flags: UInt8
    public let group: UInt16

    /// nif.xml `CollisionFilterFlags` is a bitfield over one byte: bits 0-4 are
    /// a `BipedPart`, bit 5 is `MOPP Scaled`, bit 6 is `No Collision`, bit 7 is
    /// `Linked Group`.
    public static let bipedPartMask: UInt8 = 0x1F
    public static let noCollisionFlag: UInt8 = 0x40

    /// The layers nif.xml says the biped part field is meaningful on: "Used
    /// only if the Layer is 8 (or 32/33 for Skyrim and later)" — `SKYL_BIPED`,
    /// `SKYL_DEADBIP` and `SKYL_BIPED_NO_CC`.
    public static let bipedLayers: Set<UInt8> = [8, 32, 33]

    public var isPlayerSolid: Bool {
        // SkyrimLayer 12 = trigger, 15 = non-collidable.
        layer != 12 && layer != 15 && !hasNoCollision
    }

    public var hasNoCollision: Bool {
        flags & Self.noCollisionFlag != 0
    }

    /// Which `BipedPart` this body is, or nil on a layer where the bits mean
    /// nothing. Not zero, because zero is `P_OTHER`, the neck.
    public var bipedPart: UInt8? {
        Self.bipedLayers.contains(layer) ? flags & Self.bipedPartMask : nil
    }

    /// SkyrimLayer 12 (`SKYL_TRIGGER`) specifically. Not the negation of
    /// `isPlayerSolid`: layer 15 and the `No Collision` flag also fail that
    /// test without naming a trigger.
    public var isTriggerVolume: Bool {
        layer == 12
    }
}

/// Which collision-object class carried the body. Static world geometry hangs
/// off `bhkCollisionObject`; the per-bone bodies of a character skeleton hang
/// off `bhkBlendCollisionObject`, which inherits it and appends two blend-gain
/// floats this decoder does not read.
nonisolated public enum NIFCollisionCarrier: String, Sendable {
    case collisionObject = "bhkCollisionObject"
    case blendCollisionObject = "bhkBlendCollisionObject"
}

nonisolated public struct NIFCollisionBody: Sendable {
    public let targetBlock: Int32
    /// Name of the target `NiAVObject`. On a character skeleton this is the
    /// bone the body belongs to, which is the only mapping the file carries
    /// between ragdoll bodies and the animation skeleton.
    public let targetName: String?
    /// Block index of the `bhkRigidBody`/`bhkRigidBodyT` itself, so a
    /// constraint's entity pointers can name the bodies they bind.
    public let bodyBlock: Int
    public let carrier: NIFCollisionCarrier
    public let collisionObjectFlags: UInt16
    public let worldFilter: NIFCollisionFilter
    public let rigidBodyFilter: NIFCollisionFilter
    /// NifTools hkResponseType raw values from bhkEntity + rigid-body CInfo.
    public let entityResponse: UInt8
    public let rigidBodyResponse: UInt8
    /// Mass, inertia, damping, friction, and motion classification.
    public let dynamics: NIFRigidBodyDynamics
    /// Joints this body names. A joint binds two bodies and both list it, so
    /// the same block appears twice in a model; `NIFCollisionModel.constraints`
    /// is the de-duplicated view.
    public let constraints: [NIFCollisionConstraint]
    /// nif.xml `Body Flags`: bit 1 means the body responds to wind.
    public let bodyFlags: UInt16
    /// Model-local target transform composed with bhkRigidBodyT transform.
    public let transform: float4x4
    public let shapes: [NIFCollisionShape]

    /// Raw `hkMotionType` byte. `dynamics.motionSystem` names it.
    public var motionSystem: UInt8 {
        dynamics.rawMotionSystem
    }

    public var isPlayerSolid: Bool {
        worldFilter.isPlayerSolid
            && rigidBodyFilter.isPlayerSolid
            && entityResponse == 1
            && rigidBodyResponse == 1
    }

    /// A body either of whose duplicate Havok filters names SkyrimLayer 12.
    /// Either filter is enough because vanilla trigger bodies are inconsistent
    /// about which of the two copies carries the layer. Such a body is never
    /// player-solid, so trigger routing and solid collision stay disjoint.
    public var isTriggerVolume: Bool {
        worldFilter.isTriggerVolume || rigidBodyFilter.isTriggerVolume
    }

    /// Which `BipedPart` this body is, from whichever of the two filters names a
    /// biped layer; nil outside a character. The two copies may disagree.
    public var bipedPart: UInt8? {
        worldFilter.bipedPart ?? rigidBodyFilter.bipedPart
    }

    /// Whether either filter switched this body's collision off outright.
    public var hasNoCollision: Bool {
        worldFilter.hasNoCollision || rigidBodyFilter.hasNoCollision
    }
}

nonisolated public struct NIFCollisionShape: Sendable {
    /// Body-local wrapper/chunk transform. Translation is in engine units.
    public let transform: float4x4
    public let geometry: NIFCollisionGeometry
    /// NifTools `SkyrimHavokMaterial`: the hash of the Creation Kit material
    /// name, left raw because only the plugin can resolve it. A block with
    /// several materials gives one shape per material.
    public let material: UInt32?

    public init(
        transform: float4x4,
        geometry: NIFCollisionGeometry,
        material: UInt32? = nil
    ) {
        self.transform = transform
        self.geometry = geometry
        self.material = material
    }
}

nonisolated public enum NIFCollisionGeometry: Sendable {
    /// Vertices are engine units; indices are validated triangle triples.
    case triangleSoup(vertices: [SIMD3<Float>], indices: [UInt32])
    /// Original convex points + derived hull connectivity. NIF stores points
    /// and plane normals without triangle faces; faces are clean engine data.
    case convexVertices(vertices: [SIMD3<Float>], hullIndices: [UInt32])
    case box(halfExtents: SIMD3<Float>)
    case sphere(radius: Float)
    case capsule(first: SIMD3<Float>, second: SIMD3<Float>, radius: Float)
}

nonisolated public struct NIFCollisionFailure: Equatable, Sendable {
    public let block: Int
    public let message: String
}

nonisolated public struct NIFCollisionModel: Sendable {
    /// 64 Skyrim units/yard converted to units/metre. Community constant;
    /// verified against vanilla Whiterun render/collision bounds in 4.2 probe.
    public static let havokToEngineScale: Float = 69.99125

    public let bodies: [NIFCollisionBody]
    /// Reachable shape/data variants omitted from output, grouped by block type.
    public let unsupportedReachableBlocks: [String: Int]
    /// Per-root decode failures; other roots remain available.
    public let decodeFailures: [NIFCollisionFailure]

    public var shapeCount: Int {
        bodies.reduce(0) { $0 + $1.shapes.count }
    }

    public var triangleCount: Int {
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
    public var shapeMaterials: [UInt32: Int] {
        bodies.reduce(into: [:]) { counts, body in
            for shape in body.shapes {
                guard let material = shape.material else { continue }
                counts[material, default: 0] += 1
            }
        }
    }

    public var filteredBodyCount: Int {
        bodies.count(where: { !$0.isPlayerSolid })
    }

    /// Every joint in the model, once. A joint binds two bodies and both of
    /// them list it, so the per-body arrays double-count.
    public var constraints: [NIFCollisionConstraint] {
        var seen: Set<Int> = []
        return bodies.flatMap(\.constraints).filter { seen.insert($0.block).inserted }
    }

    /// Rigid-body block index -> the name of the scene object it hangs off.
    /// On a character skeleton that is the bone name.
    public var bodyNamesByBlock: [Int: String] {
        bodies.reduce(into: [:]) { names, body in
            names[body.bodyBlock] = body.targetName
        }
    }

    /// The two bone names a joint binds, nil where the end points outside the
    /// decoded bodies or at an unnamed node.
    public func boneNames(
        of constraint: NIFCollisionConstraint
    ) -> (a: String?, b: String?) {
        let names = bodyNamesByBlock
        return (names[Int(constraint.entityA)], names[Int(constraint.entityB)])
    }

    /// Model-space AABB after composing scene-target, rigid-body, wrapper,
    /// and chunk transforms. Primitive bounds are exact before rotation and
    /// conservative after the final affine transform.
    public var bounds: ModelBounds? {
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

    /// Local-space AABB of one decoded shape. Internal because the dynamic body
    /// world needs the same box for a shape it moves every step.
    public static func bounds(of geometry: NIFCollisionGeometry) -> ModelBounds? {
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
