// Havok collision shapes in the skeleton and ragdoll files. Offsets from
// HKX2Library (MIT). Byte map: docs/formats/hkx-physics.md.

import Foundation
import simd

/// `hkpShape` and `hkpConvexShape` members every convex shape starts with.
nonisolated public struct HKPConvexHeader: Equatable, Sendable {
    public let userData: UInt64
    /// `hkcdShapeType`, as Havok stores it.
    public let shapeType: UInt32
    /// The shell around the core shape that collision keeps.
    public let radius: Float

    public static func decode(_ cursor: inout HKXObjectCursor) -> HKPConvexHeader {
        HKPConvexHeader(
            userData: cursor.uint64(at: HKXField(0x10, "m_userData")) ?? 0,
            shapeType: cursor.uint32(at: HKXField(0x18, "m_type")) ?? 0,
            radius: cursor.float32(at: HKXField(0x20, "m_radius")) ?? 0
        )
    }
}

/// Decoded `hkpCapsuleShape`, size 80: a segment from A to B with a radius.
nonisolated public struct HKPCapsuleShape: HKBClass, Equatable, Sendable {
    public let header: HKPConvexHeader
    public let vertexA: SIMD3<Float>
    public let vertexB: SIMD3<Float>
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkpCapsuleShape"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKPCapsuleShape?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKPCapsuleShape(
            header: HKPConvexHeader.decode(&cursor),
            vertexA: (cursor.vector4(at: HKXField(0x30, "m_vertexA")) ?? SIMD4()).xyz,
            vertexB: (cursor.vector4(at: HKXField(0x40, "m_vertexB")) ?? SIMD4()).xyz,
            unresolved: cursor.unresolved
        )
    }

    public var summary: String {
        "capsule radius \(header.radius), length \(simd_distance(vertexA, vertexB))"
    }
}

/// Decoded `hkpBoxShape`, size 64.
nonisolated public struct HKPBoxShape: HKBClass, Equatable, Sendable {
    public let header: HKPConvexHeader
    public let halfExtents: SIMD3<Float>
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkpBoxShape"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKPBoxShape?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKPBoxShape(
            header: HKPConvexHeader.decode(&cursor),
            halfExtents: (cursor.vector4(at: HKXField(0x30, "m_halfExtents")) ?? SIMD4()).xyz,
            unresolved: cursor.unresolved
        )
    }

    public var summary: String {
        "box half extents \(halfExtents)"
    }
}

/// Decoded `hkpConvexTranslateShape` (size 80) or `hkpConvexTransformShape`
/// (size 128): a child convex shape moved by a translation or a full transform.
nonisolated public struct HKPConvexTransformShape: Equatable, Sendable {
    public let header: HKPConvexHeader
    public let childShape: HKXPointerTarget?
    public let transform: HKTransform
    public let unresolved: [HKXUnresolvedReference]

    /// `hkpSingleShapeContainer` keeps a vtable at 0x28 and the child at 0x30.
    private static let childField = HKXField(0x30, "m_childShape.m_childShape")
    private static let placementOffset = 0x40

    static func decode(
        at target: HKXPointerTarget, in graph: HKXObjectGraph, translationOnly: Bool
    ) -> HKPConvexTransformShape? {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKPConvexHeader.decode(&cursor)
        let child = cursor.pointer(at: childField)
        let transform = if translationOnly {
            HKTransform(
                rotation: matrix_identity_float3x3,
                translation: (cursor.vector4(at: HKXField(placementOffset, "m_translation"))
                    ?? SIMD4()).xyz
            )
        } else {
            HKTransform.decode(&cursor, at: placementOffset, named: "m_transform")
        }
        return HKPConvexTransformShape(
            header: header, childShape: child, transform: transform,
            unresolved: cursor.unresolved
        )
    }

    var references: [HKBReference] {
        HKBReference.optional("m_childShape", childShape)
    }
}

nonisolated public struct HKPConvexTranslateShape: HKBClass, Equatable, Sendable {
    public let shape: HKPConvexTransformShape

    public static let className = "hkpConvexTranslateShape"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKPConvexTranslateShape?
    {
        HKPConvexTransformShape.decode(at: target, in: graph, translationOnly: true)
            .map(HKPConvexTranslateShape.init)
    }

    public var references: [HKBReference] {
        shape.references
    }

    public var unresolved: [HKXUnresolvedReference] {
        shape.unresolved
    }

    public var summary: String {
        "child moved by \(shape.transform.translation)"
    }
}

nonisolated public struct HKPConvexTransformShapeObject: HKBClass, Equatable, Sendable {
    public let shape: HKPConvexTransformShape

    public static let className = "hkpConvexTransformShape"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKPConvexTransformShapeObject?
    {
        HKPConvexTransformShape.decode(at: target, in: graph, translationOnly: false)
            .map(HKPConvexTransformShapeObject.init)
    }

    public var references: [HKBReference] {
        shape.references
    }

    public var unresolved: [HKXUnresolvedReference] {
        shape.unresolved
    }

    public var summary: String {
        "child moved to \(shape.transform.translation)"
    }
}

/// Decoded `hkpConvexVerticesShape`, size 144: a convex hull. Vertices are
/// stored four at a time as x, y, and z rows (`hkFourTransposedPoints`).
nonisolated public struct HKPConvexVerticesShape: HKBClass, Equatable, Sendable {
    public let header: HKPConvexHeader
    public let aabbHalfExtents: SIMD3<Float>
    public let aabbCenter: SIMD3<Float>
    public let vertices: [SIMD3<Float>]
    /// Outward planes as (normal, distance): a point p is inside when
    /// `dot(normal, p) + distance <= 0` for every plane.
    public let planeEquations: [SIMD4<Float>]
    public let connectivity: HKXPointerTarget?
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkpConvexVerticesShape"

    private static let rotatedVerticesField = HKXField(0x50, "m_rotatedVertices")
    private static let vertexCountField = HKXField(0x60, "m_numVertices")
    private static let planeEquationsField = HKXField(0x78, "m_planeEquations")
    private static let connectivityField = HKXField(0x88, "m_connectivity")
    private static let fourVectorsStride = 48

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKPConvexVerticesShape?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKPConvexHeader.decode(&cursor)
        let count = max(cursor.int32(at: vertexCountField) ?? 0, 0)
        let field = rotatedVerticesField
        let blocks = cursor.structArray(at: field, stride: fourVectorsStride) { element, index in
            (0 ..< 3).map { row in
                element.vector4(at: HKXField(row * 16, "m_rotatedVertices[\(index)][\(row)]"))
                    ?? SIMD4()
            }
        }
        var vertices: [SIMD3<Float>] = []
        for rows in blocks {
            for lane in 0 ..< 4 where vertices.count < count {
                vertices.append(SIMD3(rows[0][lane], rows[1][lane], rows[2][lane]))
            }
        }
        let planes = cursor.structArray(at: planeEquationsField, stride: 16) { element, index in
            element.vector4(at: HKXField(0, "m_planeEquations[\(index)]")) ?? SIMD4()
        }
        return HKPConvexVerticesShape(
            header: header,
            aabbHalfExtents: (cursor.vector4(at: HKXField(0x30, "m_aabbHalfExtents"))
                ?? SIMD4()).xyz,
            aabbCenter: (cursor.vector4(at: HKXField(0x40, "m_aabbCenter")) ?? SIMD4()).xyz,
            vertices: vertices,
            planeEquations: planes,
            connectivity: cursor.optionalPointer(at: connectivityField),
            unresolved: cursor.unresolved
        )
    }

    public var references: [HKBReference] {
        HKBReference.optional("m_connectivity", connectivity)
    }

    public var summary: String {
        "\(vertices.count) vertices, \(planeEquations.count) planes"
    }
}

/// Decoded `hkpConvexVerticesConnectivity`, size 48: the faces of a hull, as
/// vertex indices and a vertex count per face.
nonisolated public struct HKPConvexVerticesConnectivity: HKBClass, Equatable, Sendable {
    public let vertexIndices: [Int]
    public let verticesPerFace: [Int]
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkpConvexVerticesConnectivity"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKPConvexVerticesConnectivity?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let field = HKXField(0x10, "m_vertexIndices")
        let indices = cursor.structArray(at: field, stride: 2) { element, _ in
            element.uint16(at: HKXField(0, HKXField.element.name)) ?? 0
        }
        let faces = cursor.byteArray(at: HKXField(0x20, "m_numVerticesPerFace"))
            .map { $0.map(Int.init) } ?? []
        return HKPConvexVerticesConnectivity(
            vertexIndices: indices, verticesPerFace: faces, unresolved: cursor.unresolved
        )
    }

    public var summary: String {
        "\(verticesPerFace.count) faces, \(vertexIndices.count) indices"
    }
}

/// Decoded `hkpListShape`, size 144: a compound of child shapes.
nonisolated public struct HKPListShape: HKBClass, Equatable, Sendable {
    public struct Child: Equatable, Sendable {
        public let shape: HKXPointerTarget?
        public let collisionFilterInfo: UInt32
    }

    public let children: [Child]
    public let aabbHalfExtents: SIMD3<Float>
    public let aabbCenter: SIMD3<Float>
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkpListShape"

    private static let childInfoField = HKXField(0x30, "m_childInfo")
    private static let childStride = 32

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKPListShape?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let field = childInfoField
        let children = cursor.structArray(at: field, stride: childStride) { element, index in
            Child(
                shape: element.pointer(at: HKXField(0, "m_childInfo[\(index)].m_shape")),
                collisionFilterInfo: element.uint32(
                    at: HKXField(8, "m_childInfo[\(index)].m_collisionFilterInfo")
                ) ?? 0
            )
        }
        return HKPListShape(
            children: children,
            aabbHalfExtents: (cursor.vector4(at: HKXField(0x50, "m_aabbHalfExtents"))
                ?? SIMD4()).xyz,
            aabbCenter: (cursor.vector4(at: HKXField(0x60, "m_aabbCenter")) ?? SIMD4()).xyz,
            unresolved: cursor.unresolved
        )
    }

    public var references: [HKBReference] {
        HKBReference.each("m_childInfo", children.map(\.shape))
    }

    public var summary: String {
        "\(children.count) child shapes"
    }
}

/// Decoded `hkpMoppBvTreeShape`, size 112: a MOPP search tree over a child
/// collection. The tree only speeds up queries, so OpenSky reads its size.
nonisolated public struct HKPMoppBvTreeShape: HKBClass, Equatable, Sendable {
    public let code: HKXPointerTarget?
    public let childShape: HKXPointerTarget?
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkpMoppBvTreeShape"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKPMoppBvTreeShape?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKPMoppBvTreeShape(
            code: cursor.pointer(at: HKXField(0x28, "m_code")),
            childShape: cursor.pointer(at: HKXField(0x58, "m_child.m_childShape")),
            unresolved: cursor.unresolved
        )
    }

    public var references: [HKBReference] {
        HKBReference.optional("m_code", code) + HKBReference.optional("m_child", childShape)
    }

    public var summary: String {
        "MOPP tree over one child"
    }
}

/// Decoded `hkpMoppCode`, size 64: the byte code of a MOPP tree.
nonisolated public struct HKPMoppCode: HKBClass, Equatable, Sendable {
    public let offset: SIMD4<Float>
    public let byteCount: Int
    public let buildType: Int
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkpMoppCode"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKPMoppCode?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKPMoppCode(
            offset: cursor.vector4(at: HKXField(0x10, "m_info.m_offset")) ?? SIMD4(),
            byteCount: cursor.arrayCount(at: HKXField(0x20, "m_data")) ?? 0,
            buildType: cursor.int8(at: HKXField(0x30, "m_buildType")) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    public var summary: String {
        "\(byteCount) code bytes"
    }
}

/// Decoded `hkpShapeInfo`, size 128: a shape with its place in its body.
nonisolated public struct HKPShapeInfo: HKBClass, Equatable, Sendable {
    public let shape: HKXPointerTarget?
    public let isHierarchicalCompound: Bool
    public let childShapeNames: [String?]
    public let transform: HKTransform
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkpShapeInfo"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKPShapeInfo?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKPShapeInfo(
            shape: cursor.pointer(at: HKXField(0x10, "m_shape")),
            isHierarchicalCompound: cursor.bool(at: HKXField(0x18, "m_isHierarchicalCompound"))
                ?? false,
            childShapeNames: cursor.stringArray(at: HKXField(0x20, "m_childShapeNames")),
            transform: HKTransform.decode(&cursor, at: 0x40, named: "m_transform"),
            unresolved: cursor.unresolved
        )
    }

    public var references: [HKBReference] {
        HKBReference.optional("m_shape", shape)
    }

    public var summary: String {
        "shape at \(transform.translation)"
    }
}
