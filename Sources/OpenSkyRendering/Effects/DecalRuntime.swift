// Live decals: flat marks an impact leaves on a surface, such as blood under a
// struck actor. Placing one picks its size, turn, and subtexture; the oldest goes
// when the limit is reached. Pure values, so it tests without Metal. See
// docs/rendering/decals.md.

import Foundation
import OpenSkyFormatsESM
import simd

/// What one decal looks like: a `TXST` diffuse and the `DODT` that sizes and tints it.
nonisolated public struct DecalLook: Equatable, Sendable {
    /// The diffuse texture's VFS key.
    public let texture: String
    public let width: ClosedRange<Float>
    public let height: ClosedRange<Float>
    /// Linear 0-1 tint.
    public let color: SIMD3<Float>
    /// Without the flag the texture is a 2 x 2 grid of variants.
    public let hasSubtextures: Bool

    /// Nil when the decal data gives no positive size, so nothing could show.
    public init?(texture: String, decal: DecalData) {
        guard
            decal.maxWidth > 0, decal.maxHeight > 0,
            decal.maxWidth.isFinite, decal.maxHeight.isFinite
        else { return nil }
        self.texture = texture
        width = Self.range(decal.minWidth, decal.maxWidth)
        height = Self.range(decal.minHeight, decal.maxHeight)
        color = SIMD3<Float>(decal.color) / 255
        hasSubtextures = !decal.flags.contains(.noSubtextures)
    }

    private static func range(_ low: Float, _ high: Float) -> ClosedRange<Float> {
        let lower = low.isFinite ? max(min(low, high), 0) : high
        return lower ... high
    }
}

/// One placed decal. The axes are half its width and height on the surface.
nonisolated public struct Decal: Equatable, Sendable {
    public let id: Int
    public let look: DecalLook
    public let center: SIMD3<Float>
    public let axisU: SIMD3<Float>
    public let axisV: SIMD3<Float>
    /// Origin and extent of the texture cell it shows.
    public let uvRect: SIMD4<Float>

    public var normal: SIMD3<Float> {
        simd_normalize(simd_cross(axisU, axisV))
    }
}

nonisolated public struct DecalRuntime: Sendable {
    /// The game's `uMaxDecals` when the settings give none.
    public static let defaultLimit = 100
    /// A decal sits this far off its surface, so it does not flicker in the depth test.
    public static let surfaceOffset: Float = 0.5

    public var enabled = true
    /// The oldest decal goes when a new one would pass this.
    public var limit = Self.defaultLimit {
        didSet { trim() }
    }

    public private(set) var decals: [Decal] = []
    public private(set) var placedTotal = 0
    private var nextID = 1
    private var random = DecalRandom(state: 0x5DEC_A15E)

    public init() {}

    /// Places `look` on the surface at `position` facing `normal`. Nil when decals
    /// are off or the normal has no direction.
    @discardableResult
    public mutating func place(
        _ look: DecalLook,
        at position: SIMD3<Float>,
        normal: SIMD3<Float>
    ) -> Int? {
        guard enabled, limit > 0, simd_length_squared(normal) > 1e-8 else { return nil }
        let up = simd_normalize(normal)
        let (tangent, bitangent) = Self.basis(around: up, angle: random.unit() * 2 * .pi)
        let width = Self.pick(look.width, random.unit())
        let height = Self.pick(look.height, random.unit())
        let cell = look.hasSubtextures ? random.cell() : nil
        let decal = Decal(
            id: nextID,
            look: look,
            center: position + up * Self.surfaceOffset,
            axisU: tangent * (width * 0.5),
            axisV: bitangent * (height * 0.5),
            uvRect: cell.map { SIMD4(Float($0.x) * 0.5, Float($0.y) * 0.5, 0.5, 0.5) }
                ?? SIMD4(0, 0, 1, 1)
        )
        nextID += 1
        placedTotal += 1
        decals.append(decal)
        trim()
        return decal.id
    }

    public mutating func removeAll() {
        decals.removeAll()
    }

    private mutating func trim() {
        let excess = decals.count - max(limit, 0)
        if excess > 0 {
            decals.removeFirst(excess)
        }
    }

    private static func pick(_ range: ClosedRange<Float>, _ unit: Float) -> Float {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }

    /// Two directions on the plane of `normal`, turned by `angle`, with
    /// `cross(tangent, bitangent) == normal`.
    public static func basis(
        around normal: SIMD3<Float>,
        angle: Float
    ) -> (SIMD3<Float>, SIMD3<Float>) {
        let helper: SIMD3<Float> = abs(normal.z) < 0.9 ? SIMD3(0, 0, 1) : SIMD3(1, 0, 0)
        let first = simd_normalize(simd_cross(helper, normal))
        let second = simd_cross(normal, first)
        let tangent = first * cos(angle) + second * sin(angle)
        return (tangent, simd_cross(normal, tangent))
    }
}

/// A small fixed-seed generator, so a run places the same decals every time.
nonisolated struct DecalRandom: Sendable {
    var state: UInt64

    /// SplitMix64.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    /// A value in 0 ..< 1.
    mutating func unit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    mutating func cell() -> SIMD2<Int> {
        let value = Int(next() >> 62)
        return SIMD2(value & 1, value >> 1)
    }
}
