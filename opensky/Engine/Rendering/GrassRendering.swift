// Cell-owned grass placements -> shared-model instanced draw groups. CPU
// placement stays separate from GPU assembly: CellSceneBuilder loads one NIF
// per GRAS type, this layer folds every placement by mesh/material, and
// RenderScene merging preserves batches across resident cell boundaries.

import Metal
import simd

nonisolated enum GrassRenderPolicy {
    /// Hard per-frame upload/draw cap. Scene data remains resident; overflow
    /// is skipped for that frame and reported through GrassDrawStats.
    static let maximumInstancesPerFrame = 16384
    static let defaultDrawDistance: Float = 8192
    static let minimumDrawDistance: Float = 512
    static let maximumDrawDistance: Float = 16384
    static let maximumWindScale: Float = 2
    /// Shader displacement at full weather wind + maximum UI wind scale.
    static let maximumSwayDisplacement: Float = 192
}

/// One loaded GRAS model placement before it expands into mesh draw groups.
nonisolated struct GrassRenderPlacement {
    let model: RenderModel
    let transform: float4x4
    let bounds: ModelBounds?
    let position: SIMD3<Float>
    let color: SIMD3<Float>
    let wavePeriod: Float
    let phase: Float
    let densityKey: Float

    init(placement: GrassPlacement, model: RenderModel, modelBounds: ModelBounds?) {
        let resolvedTransform = GrassTransform.matrix(for: placement)
        transform = resolvedTransform
        self.model = model
        position = placement.position
        color = placement.flags.contains(.vertexLighting)
            ? placement.color : SIMD3(repeating: 1)
        wavePeriod = max(abs(placement.wavePeriod), 0.1)
        var random = GrassStableRandom(seed: Self.seed(for: placement))
        phase = random.unitFloat()
        densityKey = random.unitFloat()
        bounds = modelBounds.map {
            GrassTransform.swayBounds($0.transformed(by: resolvedTransform))
        }
    }

    private static func seed(for placement: GrassPlacement) -> UInt64 {
        UInt64(placement.grass.rawValue) &* 0x9E37_79B9_7F4A_7C15
            ^ UInt64(placement.position.x.bitPattern) << 32
            ^ UInt64(placement.position.y.bitPattern)
            ^ UInt64(placement.position.z.bitPattern) &* 0xD1B5_4A32_D192_ED03
    }
}

/// Grass-specific per-mesh instance. Matrix already includes mesh-local ->
/// model-root, matching static DrawInstance; placement metadata feeds wind,
/// density, distance fade, and runtime accounting.
nonisolated struct GrassDrawInstance {
    let modelMatrix: float4x4
    let normalMatrix: float4x4
    let bounds: ModelBounds?
    let position: SIMD3<Float>
    let color: SIMD3<Float>
    let wavePeriod: Float
    let phase: Float
    let densityKey: Float
}

nonisolated struct GrassDrawGroup {
    let mesh: RenderMesh
    let material: RenderMaterial
    fileprivate(set) var instances: [GrassDrawInstance]
}

/// Same deterministic first-appearance grouping policy as static geometry.
nonisolated struct GrassGroupAccumulator {
    private struct Key: Hashable {
        let mesh: ObjectIdentifier
        let diffuse: ObjectIdentifier
    }

    private var indexByKey: [Key: Int] = [:]
    private(set) var groups: [GrassDrawGroup] = []

    mutating func add(_ placement: GrassRenderPlacement) {
        for mesh in placement.model.meshes {
            guard mesh.materialSlot < placement.model.materials.count else { continue }
            let material = placement.model.materials[mesh.materialSlot]
            let matrix = placement.transform * mesh.localTransform
            add(
                mesh: mesh,
                material: material,
                instance: GrassDrawInstance(
                    modelMatrix: matrix,
                    normalMatrix: MatrixMath.normalMatrix(matrix),
                    bounds: placement.bounds,
                    position: placement.position,
                    color: placement.color,
                    wavePeriod: placement.wavePeriod,
                    phase: placement.phase,
                    densityKey: placement.densityKey
                )
            )
        }
    }

    mutating func add(_ group: GrassDrawGroup) {
        for instance in group.instances {
            add(mesh: group.mesh, material: group.material, instance: instance)
        }
    }

    private mutating func add(
        mesh: RenderMesh,
        material: RenderMaterial,
        instance: GrassDrawInstance
    ) {
        let key = Key(mesh: ObjectIdentifier(mesh), diffuse: ObjectIdentifier(material.diffuse))
        if let index = indexByKey[key] {
            groups[index].instances.append(instance)
        } else {
            indexByKey[key] = groups.count
            groups.append(GrassDrawGroup(mesh: mesh, material: material, instances: [instance]))
        }
    }
}

/// Pure placement orientation. Fit-to-slope maps local +Z to LAND normal;
/// yaw rotates within that tangent plane. Without flag, grass remains upright.
nonisolated enum GrassTransform {
    static func matrix(for placement: GrassPlacement) -> float4x4 {
        let up = placement.flags.contains(.fitToSlope)
            ? normalizedOrUp(placement.normal) : SIMD3<Float>(0, 0, 1)
        let reference = abs(up.y) < 0.99
            ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let tangentX = simd_normalize(simd_cross(reference, up))
        let tangentY = simd_cross(up, tangentX)
        let cosine = cosf(placement.yawRadians)
        let sine = sinf(placement.yawRadians)
        let x = (tangentX * cosine + tangentY * sine) * placement.scale.x
        let y = (-tangentX * sine + tangentY * cosine) * placement.scale.y
        let z = up * placement.scale.z
        return float4x4(columns: (
            SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(placement.position, 1)
        ))
    }

    static func swayBounds(_ bounds: ModelBounds) -> ModelBounds {
        let padding = GrassRenderPolicy.maximumSwayDisplacement
        return ModelBounds(
            min: bounds.min - SIMD3(padding, padding, 0),
            max: bounds.max + SIMD3(padding, padding, 0)
        )
    }

    private static func normalizedOrUp(_ value: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(value)
        guard length.isFinite, length > .ulpOfOne else { return SIMD3(0, 0, 1) }
        return value / length
    }
}

/// Local SplitMix64 stream: platform-stable density selection + motion phase.
nonisolated private struct GrassStableRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func unitFloat() -> Float {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Float(value >> 40) / Float(1 << 24)
    }
}
