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
}

nonisolated struct NIFCollisionBody {
    let targetBlock: Int32
    let collisionObjectFlags: UInt16
    let worldFilter: NIFCollisionFilter
    let rigidBodyFilter: NIFCollisionFilter
    /// NifTools hkResponseType raw values from bhkEntity + rigid-body CInfo.
    let entityResponse: UInt8
    let rigidBodyResponse: UInt8
    let motionSystem: UInt8
    /// Model-local target transform composed with bhkRigidBodyT transform.
    let transform: float4x4
    let shapes: [NIFCollisionShape]

    var isPlayerSolid: Bool {
        worldFilter.isPlayerSolid
            && rigidBodyFilter.isPlayerSolid
            && entityResponse == 1
            && rigidBodyResponse == 1
    }
}

nonisolated struct NIFCollisionShape {
    /// Body-local wrapper/chunk transform. Translation is in engine units.
    let transform: float4x4
    let geometry: NIFCollisionGeometry
}

nonisolated enum NIFCollisionGeometry {
    /// Vertices are engine units; indices are validated triangle triples.
    case triangleSoup(vertices: [SIMD3<Float>], indices: [UInt32])
    case convexVertices([SIMD3<Float>])
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

    var filteredBodyCount: Int {
        bodies.count(where: { !$0.isPlayerSolid })
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
        case let .triangleSoup(vertices, _), let .convexVertices(vertices):
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
