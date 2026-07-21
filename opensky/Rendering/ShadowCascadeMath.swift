// CPU-side cascaded-shadow-map math: split scheme + per-cascade light-space
// orthographic fit. Conventions match MatrixMath (RH, Metal clip z in [0, 1],
// Skyrim Z-up world). No Metal device needed — pure, unit-tested geometry.
// References: practical split scheme (Zhang et al., "Parallel-Split Shadow
// Maps"), stable texel-snapping fit (Microsoft CascadedShadowMaps11 sample).

import simd

/// One sun-shadow cascade: orthographic light-space transform plus the
/// view-space depth range of the camera-frustum slice it covers.
struct ShadowCascade {
    var viewProjection: simd_float4x4
    var splitNear: Float
    var splitFar: Float
}

nonisolated enum ShadowCascadeMath {
    /// Practical (blended uniform + logarithmic) split scheme. Returns `count`
    /// strictly increasing far bounds; last element is exactly `far`. Degenerate
    /// input is clamped to a sane range rather than crashing.
    static func splitDistances(near: Float, far: Float, count: Int, lambda: Float) -> [Float] {
        let steps = max(count, 1)
        let safeNear = max(near, 1e-4)
        let safeFar = max(far, safeNear * (1 + 1e-4))
        let blend = min(max(lambda, 0), 1)
        let ratio = safeFar / safeNear
        let range = safeFar - safeNear
        var splits = [Float](repeating: 0, count: steps)
        for step in 1 ... steps {
            let fraction = Float(step) / Float(steps)
            let uniform = safeNear + range * fraction
            let logarithmic = safeNear * powf(ratio, fraction)
            splits[step - 1] = blend * logarithmic + (1 - blend) * uniform
        }
        // pow rounding can drift the endpoint; pin it exactly to `far`.
        splits[steps - 1] = safeFar
        return splits
    }

    // Full camera + sun + cascade config; the renderer calls this by keyword.
    // swiftlint:disable function_parameter_count
    /// Build one orthographic light-space cascade per frustum slice. Slice 0
    /// starts at `nearPlane`; `shadowDistance` is the overall far bound. Each
    /// cascade fits a rotation-invariant square around the slice's bounding
    /// sphere and snaps its origin to the shadow-map texel grid.
    static func makeCascades(
        cameraToWorld: simd_float4x4,
        fovYRadians: Float,
        aspectRatio: Float,
        nearPlane: Float,
        shadowDistance: Float,
        sunDirection: SIMD3<Float>,
        cascadeCount: Int,
        lambda: Float,
        shadowMapResolution: Int,
        casterBackup: Float,
        residentBounds: ModelBounds? = nil
    ) -> [ShadowCascade] {
        let count = max(cascadeCount, 1)
        let resolution = max(shadowMapResolution, 1)
        let sun = normalizedSun(sunDirection)
        let up = lightUp(sun)
        let tanHalfFovY = tanf(max(fovYRadians, 1e-4) * 0.5)
        let splits = splitDistances(
            near: nearPlane,
            far: shadowDistance,
            count: count,
            lambda: lambda
        )
        var cascades: [ShadowCascade] = []
        cascades.reserveCapacity(count)
        for index in 0 ..< count {
            let sliceNear = index == 0 ? nearPlane : splits[index - 1]
            let sliceFar = splits[index]
            let corners = sliceCorners(
                cameraToWorld: cameraToWorld,
                tanHalfFovY: tanHalfFovY,
                aspectRatio: aspectRatio,
                sliceNear: sliceNear,
                sliceFar: sliceFar
            )
            let viewProjection = fitCascade(
                corners: corners,
                sun: sun,
                up: up,
                resolution: resolution,
                casterBackup: casterBackup,
                residentBounds: residentBounds
            )
            cascades.append(ShadowCascade(
                viewProjection: viewProjection,
                splitNear: sliceNear,
                splitFar: sliceFar
            ))
        }
        return cascades
    }

    // swiftlint:enable function_parameter_count

    /// Cascade lookup mirrored by the MSL shader: first `i` in `0..<cascadeCount`
    /// with `viewDepth <= splits[i]`, else the last cascade. Written as a plain
    /// descending scan (no break) so the shader can mirror it verbatim.
    static func cascadeIndex(viewDepth: Float, splits: SIMD4<Float>, cascadeCount: Int) -> Int {
        let count = min(max(cascadeCount, 1), 4)
        var index = count - 1
        var slot = count - 1
        while slot >= 0 {
            if viewDepth <= splits[slot] {
                index = slot
            }
            slot -= 1
        }
        return index
    }

    // MARK: - Internal helpers (also used by tests to reconstruct the fit)

    /// Light-space up vector: world Z-up, switched to +X when the sun points
    /// (anti)parallel to Z so `lookAt` never degenerates.
    static func lightUp(_ sunDirection: SIMD3<Float>) -> SIMD3<Float> {
        let zUp = SIMD3<Float>(0, 0, 1)
        return abs(simd_dot(sunDirection, zUp)) > 0.99 ? SIMD3<Float>(1, 0, 0) : zUp
    }

    /// Unit sun-travel direction; falls back to straight-down for a zero vector.
    static func normalizedSun(_ sunDirection: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(sunDirection)
        return length > 1e-6 ? sunDirection / length : SIMD3<Float>(0, 0, -1)
    }

    /// Eight world-space corners of the camera-frustum slice `[sliceNear, sliceFar]`.
    static func sliceCorners(
        cameraToWorld: simd_float4x4,
        tanHalfFovY: Float,
        aspectRatio: Float,
        sliceNear: Float,
        sliceFar: Float
    ) -> [SIMD3<Float>] {
        var corners: [SIMD3<Float>] = []
        corners.reserveCapacity(8)
        for depth in [sliceNear, sliceFar] {
            let halfHeight = depth * tanHalfFovY
            let halfWidth = halfHeight * aspectRatio
            for signY in [Float(-1), 1] {
                for signX in [Float(-1), 1] {
                    let eye = SIMD4<Float>(signX * halfWidth, signY * halfHeight, -depth, 1)
                    let world = cameraToWorld * eye
                    corners.append(SIMD3<Float>(world.x, world.y, world.z))
                }
            }
        }
        return corners
    }

    /// Bounding sphere (centroid + enclosing radius) of the slice corners.
    static func boundingSphere(_ corners: [SIMD3<Float>]) -> (center: SIMD3<Float>, radius: Float) {
        var center = SIMD3<Float>(0, 0, 0)
        for corner in corners {
            center += corner
        }
        center /= Float(max(corners.count, 1))
        var radius: Float = 0
        for corner in corners {
            radius = max(radius, simd_length(corner - center))
        }
        return (center, max(radius, 1e-4))
    }

    /// Light view-projection for one slice: sphere-fit square ortho box, origin
    /// snapped to the texel grid, near plane extended toward the sun by
    /// `casterBackup` so casters between the sun and the slice still render.
    static func fitCascade(
        corners: [SIMD3<Float>],
        sun: SIMD3<Float>,
        up: SIMD3<Float>,
        resolution: Int,
        casterBackup: Float,
        residentBounds: ModelBounds? = nil
    ) -> simd_float4x4 {
        let sphere = boundingSphere(corners)
        let lightView = MatrixMath.lookAt(
            eye: sphere.center - sun * sphere.radius,
            target: sphere.center,
            up: up
        )
        var minBound = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxBound = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for corner in corners {
            let lightSpace = lightView * SIMD4<Float>(corner.x, corner.y, corner.z, 1)
            minBound = simd_min(minBound, SIMD3<Float>(lightSpace.x, lightSpace.y, lightSpace.z))
            maxBound = simd_max(maxBound, SIMD3<Float>(lightSpace.x, lightSpace.y, lightSpace.z))
        }
        // Fixed square extent (sphere diameter) keeps the texel size stable as
        // the camera rotates; +2 texels of border guarantees the corners stay
        // inside after the origin snaps down to the grid.
        let diameter = 2 * sphere.radius
        let texelSize = diameter / Float(resolution)
        let extent = diameter + 2 * texelSize
        let originX = (minBound.x / texelSize).rounded(.down) * texelSize
        let originY = (minBound.y / texelSize).rounded(.down) * texelSize
        // Eye space looks down -z: nearest corner has the largest (least
        // negative) z, so slice near = -maxZ. The casterBackup extension is
        // clamped to resident geometry so it never reaches past what exists.
        let sliceNearZ = -maxBound.z
        let residentNearZ = residentBounds.map {
            residentNearLightZ($0, lightView: lightView)
        }
        let nearZ = clampedShadowNearZ(
            sliceNearZ: sliceNearZ,
            fullBackupNearZ: sliceNearZ - casterBackup,
            residentNearZ: residentNearZ
        )
        let farZ = max(-minBound.z, nearZ + 1e-4)
        let ortho = MatrixMath.orthographic(
            left: originX,
            right: originX + extent,
            bottom: originY,
            top: originY + extent,
            nearZ: nearZ,
            farZ: farZ
        )
        return ortho * lightView
    }

    /// Nearest-toward-sun light-space near distance of a world AABB: the max
    /// light-space z of its eight corners, negated into
    /// MatrixMath.orthographic's positive near-distance convention (eye looks
    /// down -z, so the corner closest to the sun has the largest z).
    static func residentNearLightZ(_ bounds: ModelBounds, lightView: simd_float4x4) -> Float {
        var maxZ = -Float.greatestFiniteMagnitude
        for corner in bounds.corners {
            let z = (lightView * SIMD4<Float>(corner.x, corner.y, corner.z, 1)).z
            maxZ = max(maxZ, z)
        }
        return -maxZ
    }

    /// Clamp the light near plane so the casterBackup extension reaches no
    /// further toward the sun than resident geometry actually does. The scene
    /// is the resident cell set, so its bounds enclose every caster: pulling
    /// the near plane back to them is a precision/cost win, never a visual
    /// change. `sliceNearZ` keeps the frustum slice covered; `fullBackupNearZ`
    /// is the unclamped 7.1.1 near; `residentNearZ` nil -> unclamped. The
    /// result stays <= sliceNearZ (slice covered) and, whenever resident
    /// geometry sits within the backup, <= residentNearZ (no caster clipped),
    /// and never reaches past the full backup toward the sun.
    static func clampedShadowNearZ(
        sliceNearZ: Float,
        fullBackupNearZ: Float,
        residentNearZ: Float?
    ) -> Float {
        guard let residentNearZ else { return fullBackupNearZ }
        return min(sliceNearZ, max(fullBackupNearZ, residentNearZ))
    }
}
