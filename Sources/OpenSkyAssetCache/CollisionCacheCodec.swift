// A decoded collision model as cache bytes: bodies, their filters and dynamics,
// and every shape's ready arrays. Models with joints are not cached, because
// their constraint data has no fixed layout; they load from the NIF.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import simd

nonisolated public enum CollisionCacheCodec {
    /// True when every part of `model` fits this payload.
    public static func canEncode(_ model: NIFCollisionModel) -> Bool {
        model.bodies.allSatisfy(\.constraints.isEmpty)
    }

    /// Nil for a model with joints.
    public static func encode(_ model: NIFCollisionModel) -> Data? {
        guard canEncode(model) else { return nil }
        var out = CachePayloadWriter()
        let unsupported = model.unsupportedReachableBlocks.sorted { $0.key < $1.key }
        out.strings(unsupported.map(\.key))
        out.array(unsupported.map { Int64($0.value) })
        out.array(model.decodeFailures.map { Int64($0.block) })
        out.strings(model.decodeFailures.map(\.message))
        out.int(model.bodies.count)
        model.bodies.forEach { encode($0, into: &out) }
        return out.data
    }

    public static func decode(_ data: Data) throws -> NIFCollisionModel {
        var input = CachePayloadReader(data)
        let names = try input.strings()
        let counts = try input.array(Int64.self)
        let failureBlocks = try input.array(Int64.self)
        let failureMessages = try input.strings()
        guard names.count == counts.count, failureBlocks.count == failureMessages.count else {
            throw CachePayloadError.badCount(names.count)
        }
        let bodyCount = try ModelCacheCodec.count(input.int(), in: data)
        let bodies = try (0 ..< bodyCount).map { _ in try body(&input) }
        guard input.isAtEnd else { throw CachePayloadError.truncated }
        return NIFCollisionModel(
            bodies: bodies,
            unsupportedReachableBlocks: Dictionary(
                zip(names, counts.map { Int($0) }), uniquingKeysWith: { first, _ in first }
            ),
            decodeFailures: zip(failureBlocks, failureMessages).map {
                NIFCollisionFailure(block: Int($0), message: $1)
            }
        )
    }

    private static func encode(_ body: NIFCollisionBody, into out: inout CachePayloadWriter) {
        out.value(body.targetBlock)
        out.string(body.targetName)
        out.int(body.bodyBlock)
        out.string(body.carrier.rawValue)
        out.value(body.collisionObjectFlags)
        out.value(body.worldFilter)
        out.value(body.rigidBodyFilter)
        out.value(body.entityResponse)
        out.value(body.rigidBodyResponse)
        out.value(body.dynamics)
        out.value(body.bodyFlags)
        out.value(body.transform)
        out.int(body.shapes.count)
        body.shapes.forEach { encode($0, into: &out) }
    }

    private static func body(_ input: inout CachePayloadReader) throws -> NIFCollisionBody {
        let targetBlock = try input.value(Int32.self)
        let targetName = try input.string()
        let bodyBlock = try input.int()
        let carrierName = try input.string() ?? ""
        guard let carrier = NIFCollisionCarrier(rawValue: carrierName) else {
            throw CachePayloadError.badTag(0)
        }
        let objectFlags = try input.value(UInt16.self)
        let worldFilter = try input.value(NIFCollisionFilter.self)
        let rigidBodyFilter = try input.value(NIFCollisionFilter.self)
        let entityResponse = try input.value(UInt8.self)
        let rigidBodyResponse = try input.value(UInt8.self)
        let dynamics = try input.value(NIFRigidBodyDynamics.self)
        let bodyFlags = try input.value(UInt16.self)
        let transform = try input.value(float4x4.self)
        let shapeCount = try input.int()
        guard (0 ... 1 << 20).contains(shapeCount)
        else { throw CachePayloadError.badCount(shapeCount) }
        let shapes = try (0 ..< shapeCount).map { _ in try shape(&input) }
        return NIFCollisionBody(
            targetBlock: targetBlock, targetName: targetName, bodyBlock: bodyBlock,
            carrier: carrier,
            collisionObjectFlags: objectFlags, worldFilter: worldFilter,
            rigidBodyFilter: rigidBodyFilter, entityResponse: entityResponse,
            rigidBodyResponse: rigidBodyResponse, dynamics: dynamics, constraints: [],
            bodyFlags: bodyFlags, transform: transform, shapes: shapes
        )
    }

    private static func encode(_ shape: NIFCollisionShape, into out: inout CachePayloadWriter) {
        out.value(shape.transform)
        out.array(shape.material.map { [$0] } ?? [])
        switch shape.geometry {
        case let .triangleSoup(vertices, indices):
            out.tag(1)
            out.array(vertices)
            out.array(indices)
        case let .convexVertices(vertices, hullIndices):
            out.tag(2)
            out.array(vertices)
            out.array(hullIndices)
        case let .box(halfExtents):
            out.tag(3)
            out.value(halfExtents)
        case let .sphere(radius):
            out.tag(4)
            out.value(radius)
        case let .capsule(first, second, radius):
            out.tag(5)
            out.array([first, second])
            out.value(radius)
        }
    }

    private static func shape(_ input: inout CachePayloadReader) throws -> NIFCollisionShape {
        let transform = try input.value(float4x4.self)
        let material = try input.array(UInt32.self).first
        let geometry: NIFCollisionGeometry
        switch try input.tag() {
        case 1: geometry = try .triangleSoup(vertices: input.array(), indices: input.array())
        case 2: geometry = try .convexVertices(vertices: input.array(), hullIndices: input.array())
        case 3: geometry = try .box(halfExtents: input.value())
        case 4: geometry = try .sphere(radius: input.value())
        case 5:
            let ends = try input.array(SIMD3<Float>.self)
            guard ends.count == 2 else { throw CachePayloadError.badCount(ends.count) }
            geometry = try .capsule(first: ends[0], second: ends[1], radius: input.value())
        case let other: throw CachePayloadError.badTag(other)
        }
        return NIFCollisionShape(transform: transform, geometry: geometry, material: material)
    }
}
