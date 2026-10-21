// Collision blocks beside the rigid body path: the shape phantom and its
// collision object, the cylinder and plane shapes, the breakable constraint, and
// the ball-and-socket chain. Layout: docs/formats/nif-collision.md.

import Foundation
import OpenSkyFormatsCore
import simd

/// nif.xml `bhkNiCollisionObject`: the target node, flags, and the body or phantom.
nonisolated public struct NIFCollisionObjectBlock: Equatable, Sendable {
    public static let phantomType = "bhkSPCollisionObject"

    public let targetRef: Int32
    public let flags: UInt16
    public let bodyRef: Int32

    public init(reader: inout BinaryReader) throws {
        targetRef = try reader.readNIFRef()
        flags = try reader.readUInt16()
        bodyRef = try reader.readNIFRef()
    }
}

/// `bhkSimpleShapePhantom`: a shape that reports overlaps and pushes nothing.
nonisolated public struct NIFShapePhantom: Sendable {
    public static let typeName = "bhkSimpleShapePhantom"

    public let shapeRef: Int32
    public let filter: NIFCollisionFilter
    /// Phantom to target node, translation in engine units.
    public let transform: float4x4

    public init(reader: inout BinaryReader) throws {
        shapeRef = try reader.readNIFRef()
        filter = try NIFCollisionFilter(
            layer: reader.readUInt8(), flags: reader.readUInt8(), group: reader.readUInt16()
        )
        reader.skip(20 + 8) // bhkWorldObjectCInfo, unused bytes
        transform = try reader.readCollisionMatrix()
    }
}

/// `bhkCylinderShape`: a cylinder between two points.
nonisolated public struct NIFCylinderShape: Equatable, Sendable {
    public static let typeName = "bhkCylinderShape"
    /// Sides of the prism that stands in for the round wall.
    static let sides = 12

    public let material: UInt32
    public let first: SIMD3<Float>
    public let second: SIMD3<Float>
    /// Engine units.
    public let radius: Float

    public init(reader: inout BinaryReader) throws {
        material = try reader.readUInt32()
        reader.skip(4 + 8) // shell radius, unused bytes
        let scale = NIFCollisionModel.havokToEngineScale
        first = try reader.readVector4().xyz * scale
        second = try reader.readVector4().xyz * scale
        radius = try reader.readFloat32() * scale
        reader.skip(12)
    }

    /// A prism around the axis, with its hull, so the convex path collides with it.
    public var geometry: NIFCollisionGeometry {
        let axis = second - first
        let length = simd_length(axis)
        guard length > .ulpOfOne, radius > 0 else { return .sphere(radius: max(radius, 0)) }
        let up = axis / length
        let side = simd_normalize(simd_cross(up, abs(up.z) < 0.9 ? SIMD3(0, 0, 1) : SIMD3(1, 0, 0)))
        let other = simd_cross(up, side)
        var vertices: [SIMD3<Float>] = []
        var planes: [SIMD4<Float>] = [
            SIMD4(-up, simd_dot(up, first)),
            SIMD4(up, -simd_dot(up, second))
        ]
        for index in 0 ..< Self.sides {
            let angle = Float(index) / Float(Self.sides) * 2 * .pi
            let ring = side * cos(angle) * radius + other * sin(angle) * radius
            vertices += [first + ring, second + ring]
            let middle = angle + .pi / Float(Self.sides)
            let normal = side * cos(middle) + other * sin(middle)
            planes.append(SIMD4(normal, -simd_dot(normal, first + ring)))
        }
        return .convexVertices(
            vertices: vertices,
            hullIndices: NIFCollisionConvexHull.indices(vertices: vertices, planes: planes)
        )
    }
}

/// `bhkPlaneShape`: a plane, bounded by a box.
nonisolated public struct NIFPlaneShape: Equatable, Sendable {
    public static let typeName = "bhkPlaneShape"

    public let material: UInt32
    public let normal: SIMD3<Float>
    /// Engine units from the origin along the normal.
    public let constant: Float
    public let halfExtents: SIMD3<Float>
    public let center: SIMD3<Float>

    public init(reader: inout BinaryReader) throws {
        material = try reader.readUInt32()
        reader.skip(12)
        let scale = NIFCollisionModel.havokToEngineScale
        normal = try reader.readVector3()
        constant = try reader.readFloat32() * scale
        halfExtents = try reader.readVector4().xyz * scale
        center = try reader.readVector4().xyz * scale
    }

    /// The part of the plane inside the box, as two triangles.
    public var geometry: NIFCollisionGeometry {
        let length = simd_length(normal)
        guard length > .ulpOfOne else { return .triangleSoup(vertices: [], indices: []) }
        let unit = normal / length
        let onPlane = center - unit * (simd_dot(unit, center) - constant / length)
        let side = simd_normalize(simd_cross(
            unit,
            abs(unit.z) < 0.9 ? SIMD3(0, 0, 1) : SIMD3(1, 0, 0)
        ))
        let other = simd_cross(unit, side)
        let reach = simd_length(halfExtents)
        let corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)].map { signs in
            let point = onPlane + side * Float(signs.0) * reach + other * Float(signs.1) * reach
            return simd_clamp(point, center - halfExtents, center + halfExtents)
        }
        return .triangleSoup(vertices: corners, indices: [0, 1, 2, 0, 2, 3])
    }
}

/// `bhkBallSocketConstraintChain`: entity `i` and entity `i + 1` share pivot pair `i`.
nonisolated public struct NIFBallSocketChain: Sendable {
    public static let typeName = "bhkBallSocketConstraintChain"

    public let links: [NIFBallAndSocketConstraint]
    public let tau: Float
    public let damping: Float
    public let constraintForceMixing: Float
    public let maxErrorDistance: Float
    public let entities: [Int32]

    public init(reader: inout BinaryReader) throws {
        let pivots = try reader.readNIFCount(stride: 16, label: "chain pivot")
        links = try (0 ..< pivots / 2).map { _ in
            try NIFBallAndSocketConstraint(
                pivotA: reader.readHavokPoint(),
                pivotB: reader.readHavokPoint()
            )
        }
        tau = try reader.readFloat32()
        damping = try reader.readFloat32()
        constraintForceMixing = try reader.readFloat32()
        maxErrorDistance = try reader.readFloat32()
        entities = try reader.readNIFRefs(label: "chained entity")
        reader.skip(16) // bhkConstraintCInfo, which repeats the first two entities
    }

    /// One ball-and-socket joint per link, each with the chain's block index.
    public func constraints(block: Int) -> [NIFCollisionConstraint] {
        links.enumerated().compactMap { link, joint in
            guard link + 1 < entities.count else { return nil }
            var constraint = NIFCollisionConstraint(
                block: block, entityA: entities[link], entityB: entities[link + 1], priority: 1,
                data: .ballAndSocket(joint)
            )
            constraint.link = link
            return constraint
        }
    }
}

nonisolated extension NIFBlockDecoders {
    static let collision: [String: Decode] = [
        NIFCollisionObjectBlock
            .phantomType: { reader, _ in try NIFCollisionObjectBlock(reader: &reader) },
        NIFShapePhantom.typeName: { reader, _ in try NIFShapePhantom(reader: &reader) },
        NIFCylinderShape.typeName: { reader, _ in try NIFCylinderShape(reader: &reader) },
        NIFPlaneShape.typeName: { reader, _ in try NIFPlaneShape(reader: &reader) },
        NIFBallSocketChain.typeName: { reader, _ in try NIFBallSocketChain(reader: &reader) },
        NIFConstraintDecoder.breakableType: { reader, _ in
            try NIFConstraintDecoder.decode(
                reader: &reader,
                typeName: NIFConstraintDecoder.breakableType,
                index: -1
            )
        }
    ]
}
