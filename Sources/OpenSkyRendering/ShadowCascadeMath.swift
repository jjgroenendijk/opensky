// CPU-side cascaded-shadow-map math: split scheme + per-cascade light-space
// orthographic fit. Conventions match MatrixMath (RH, Metal clip z in [0, 1],
// Skyrim Z-up world). No Metal device needed — pure, unit-tested geometry.
// References: practical split scheme (Zhang et al., "Parallel-Split Shadow
// Maps"), stable texel-snapping fit (Microsoft CascadedShadowMaps11 sample).

import OpenSkyFormatsCore
import simd

/// One sun-shadow cascade: orthographic light-space transform plus the
/// view-space depth range of the camera-frustum slice it covers.
nonisolated public struct ShadowCascade: Sendable {
    public var viewProjection: simd_float4x4
    public var splitNear: Float
    public var splitFar: Float
}

/// Camera, sun, and cascade settings for `ShadowCascadeMath.makeCascades`.
/// Slice 0 starts at `nearPlane`; `shadowDistance` is the overall far bound.
nonisolated public struct ShadowCascadeRequest: Sendable {
    public var cameraToWorld: simd_float4x4
    public var fovYRadians: Float
    public var aspectRatio: Float
    public var nearPlane: Float
    public var shadowDistance: Float
    public var sunDirection: SIMD3<Float>
    public var cascadeCount: Int
    public var lambda: Float
    public var shadowMapResolution: Int
    public var casterBackup: Float
    public var residentBounds: ModelBounds?

    public init(
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
    ) {
        self.cameraToWorld = cameraToWorld
        self.fovYRadians = fovYRadians
        self.aspectRatio = aspectRatio
        self.nearPlane = nearPlane
        self.shadowDistance = shadowDistance
        self.sunDirection = sunDirection
        self.cascadeCount = cascadeCount
        self.lambda = lambda
        self.shadowMapResolution = shadowMapResolution
        self.casterBackup = casterBackup
        self.residentBounds = residentBounds
    }
}

nonisolated public enum ShadowCascadeMath: Sendable {
    /// Practical (blended uniform + logarithmic) split scheme. Returns `count`
    /// strictly increasing far bounds; last element is exactly `far`. Degenerate
    /// input is clamped to a sane range rather than crashing.
    public static func splitDistances(
        near: Float,
        far: Float,
        count: Int,
        lambda: Float
    ) -> [Float] {
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

    /// One orthographic light-space cascade per frustum slice. Each cascade
    /// fits a rotation-invariant square around its slice's bounding sphere and
    /// snaps the origin to the shadow-map texel grid.
    public static func makeCascades(_ request: ShadowCascadeRequest) -> [ShadowCascade] {
        let count = max(request.cascadeCount, 1)
        let resolution = max(request.shadowMapResolution, 1)
        let sun = normalizedSun(request.sunDirection)
        let up = lightUp(sun)
        let tanHalfFovY = tanf(max(request.fovYRadians, 1e-4) * 0.5)
        let splits = splitDistances(
            near: request.nearPlane,
            far: request.shadowDistance,
            count: count,
            lambda: request.lambda
        )
        var cascades: [ShadowCascade] = []
        cascades.reserveCapacity(count)
        for index in 0 ..< count {
            let sliceNear = index == 0 ? request.nearPlane : splits[index - 1]
            let sliceFar = splits[index]
            let corners = sliceCorners(
                cameraToWorld: request.cameraToWorld,
                tanHalfFovY: tanHalfFovY,
                aspectRatio: request.aspectRatio,
                sliceNear: sliceNear,
                sliceFar: sliceFar
            )
            let viewProjection = fitCascade(
                corners: corners,
                sun: sun,
                up: up,
                resolution: resolution,
                casterBackup: request.casterBackup,
                residentBounds: request.residentBounds
            )
            cascades.append(ShadowCascade(
                viewProjection: viewProjection,
                splitNear: sliceNear,
                splitFar: sliceFar
            ))
        }
        return cascades
    }

    /// Cascade lookup mirrored by the MSL shader: first `i` in `0..<cascadeCount`
    /// with `viewDepth <= splits[i]`, else the last cascade. Written as a plain
    /// descending scan (no break) so the shader can mirror it verbatim.
    public static func cascadeIndex(
        viewDepth: Float,
        splits: SIMD4<Float>,
        cascadeCount: Int
    ) -> Int {
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
    public static func lightUp(_ sunDirection: SIMD3<Float>) -> SIMD3<Float> {
        let zUp = SIMD3<Float>(0, 0, 1)
        return abs(simd_dot(sunDirection, zUp)) > 0.99 ? SIMD3<Float>(1, 0, 0) : zUp
    }

    /// Unit sun-travel direction; falls back to straight-down for a zero vector.
    public static func normalizedSun(_ sunDirection: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(sunDirection)
        return length > 1e-6 ? sunDirection / length : SIMD3<Float>(0, 0, -1)
    }

    /// Eight world-space corners of the camera-frustum slice `[sliceNear, sliceFar]`.
    public static func sliceCorners(
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
    public static func boundingSphere(_ corners: [SIMD3<Float>])
        -> (center: SIMD3<Float>, radius: Float)
    {
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
    public static func fitCascade(
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
        let ortho = MatrixMath.orthographic(OrthographicBounds(
            left: originX,
            right: originX + extent,
            bottom: originY,
            top: originY + extent,
            nearZ: nearZ,
            farZ: farZ
        ))
        return ortho * lightView
    }

    /// Nearest-toward-sun light-space near distance of a world AABB: the max
    /// light-space z of its eight corners, negated into
    /// MatrixMath.orthographic's positive near-distance convention (eye looks
    /// down -z, so the corner closest to the sun has the largest z).
    public static func residentNearLightZ(
        _ bounds: ModelBounds,
        lightView: simd_float4x4
    ) -> Float {
        var maxZ = -Float.greatestFiniteMagnitude
        for corner in bounds.corners {
            let z = (lightView * SIMD4<Float>(corner.x, corner.y, corner.z, 1)).z
            maxZ = max(maxZ, z)
        }
        return -maxZ
    }

    /// Pulls the light near plane back to resident geometry, which bounds every
    /// caster. The result covers the slice, clips no resident caster, and never
    /// reaches past `fullBackupNearZ`. A nil `residentNearZ` means no clamp.
    public static func clampedShadowNearZ(
        sliceNearZ: Float,
        fullBackupNearZ: Float,
        residentNearZ: Float?
    ) -> Float {
        guard let residentNearZ else { return fullBackupNearZ }
        return min(sliceNearZ, max(fullBackupNearZ, residentNearZ))
    }
}
