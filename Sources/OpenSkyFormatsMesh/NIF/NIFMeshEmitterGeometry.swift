// Geometry of the shapes an `NiPSysMeshEmitter` births on. Skinned shapes use
// their bind pose. Layout: docs/formats/nif-particles.md.

import Foundation
import simd

nonisolated enum NIFMeshEmitterGeometry {
    /// Bounds memory for a hostile file; vanilla emitter meshes are far smaller.
    static let maximumVertices = 65536

    /// The shape behind an emitter mesh ref; nil for a block type that holds none.
    static func shape(_ block: NIFFile.Block, _ file: NIFFile) throws -> NIFTriShape? {
        switch block.typeName {
        case "BSTriShape":
            try NIFTriShape(data: block.data, header: file.header)
        case "BSSubIndexTriShape":
            try NIFSubIndexTriShape(data: block.data, header: file.header).shape
        case "BSDynamicTriShape":
            try NIFDynamicTriShape(data: block.data, header: file.header).shape
        default:
            nil
        }
    }

    static func append(
        _ shape: NIFTriShape,
        transform: float4x4,
        to source: inout MeshEmitterSource
    ) {
        let first = source.positions.count
        guard
            !shape.positions.isEmpty,
            first + shape.positions.count <= maximumVertices
        else { return }
        let hasNormals = shape.normals.count == shape.positions.count
            && source.normals.count == first
        let normalMatrix = simd_float3x3(
            SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        ).inverse.transpose
        for (index, position) in shape.positions.enumerated() {
            let moved = transform * SIMD4(position, 1)
            source.positions.append(SIMD3(moved.x, moved.y, moved.z))
            if hasNormals {
                let normal = normalMatrix * shape.normals[index]
                let length = simd_length(normal)
                source.normals.append(length > 1e-6 ? normal / length : SIMD3(0, 0, 1))
            }
        }
        if !hasNormals {
            source.normals.removeAll()
        }
        var index = 0
        while index + 2 < shape.indices.count {
            let triangle = SIMD3(
                UInt32(shape.indices[index]), UInt32(shape.indices[index + 1]),
                UInt32(shape.indices[index + 2])
            )
            index += 3
            guard triangle.max() < UInt32(shape.positions.count) else { continue }
            source.triangles.append(triangle &+ UInt32(first))
        }
    }
}

nonisolated extension ParticleEmitter {
    func replacingShape(_ shape: Shape) -> ParticleEmitter {
        ParticleEmitter(
            name: name, order: order, active: active, speed: speed,
            speedVariation: speedVariation, declination: declination,
            declinationVariation: declinationVariation, planarAngle: planarAngle,
            planarAngleVariation: planarAngleVariation, initialColor: initialColor,
            initialRadius: initialRadius, radiusVariation: radiusVariation,
            lifeSpan: lifeSpan, lifeSpanVariation: lifeSpanVariation, shape: shape
        )
    }
}
