// Rain and snow scales taken from the `SPGD` record the active weather names.
// The hand-tuned volumes were tuned to the vanilla records, so a record is read
// as a ratio to its anchor. See docs/formats/environment-shading.md, section
// "Precipitation mapping".

import Foundation
import OpenSkyFormatsESM

/// The hand-tuned values a precipitation scale of 1 keeps.
nonisolated public struct PrecipitationBase: Equatable, Sendable {
    public static let rain = PrecipitationBase(speed: 1900, radius: 12, emission: 6)
    public static let snow = PrecipitationBase(speed: 360, radius: 5, emission: 4)

    public let speed: Float
    public let radius: Float
    /// Multiplies the shared particle birth rate.
    public let emission: Float
}

/// How one precipitation volume differs from its hand-tuned look.
nonisolated public struct PrecipitationScale: Equatable, Sendable {
    public static let identity = PrecipitationScale(speed: 1, size: 1, density: 1)
    /// A ratio stays inside this range, so an odd record cannot empty or flood the volume.
    public static let range: ClosedRange<Float> = 0.25 ... 4

    public let speed: Float
    public let size: Float
    public let density: Float

    public init(speed: Float, size: Float, density: Float) {
        self.speed = Self.clamped(speed)
        self.size = Self.clamped(size)
        self.density = Self.clamped(density)
    }

    private static func clamped(_ value: Float) -> Float {
        guard value.isFinite else { return 1 }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// The `SPGD` values the hand-tuned volumes match: vanilla `RainParticles` and
/// `SnowParticlesMed`, read from the install's census.
nonisolated public struct PrecipitationAnchor: Equatable, Sendable {
    public static let rain = PrecipitationAnchor(gravity: 675, size: SIMD2(0.35, 2), density: 1)
    public static let snow = PrecipitationAnchor(gravity: 100, size: SIMD2(1, 1), density: 3)

    public let gravity: Float
    public let size: SIMD2<Float>
    public let density: Float
}

/// Which volume a record feeds and how. `SPGD` type 0 is rain, type 1 is snow.
nonisolated public struct PrecipitationTuning: Equatable, Sendable {
    public static let fallback = PrecipitationTuning(rain: .identity, snow: .identity, source: nil)

    public var rain: PrecipitationScale
    public var snow: PrecipitationScale
    /// The record's editor ID, nil for the fallback.
    public var source: String?
    /// Length over width of a rain streak: the rain record's particle size Y over X.
    public var rainStreakAspect = Self.aspect(PrecipitationAnchor.rain.size)
    /// The snow record's texture and its grid of flake cells; nil keeps the generated flake.
    public var snowLook: PrecipitationLook?

    public init(rain: PrecipitationScale, snow: PrecipitationScale, source: String?) {
        self.rain = rain
        self.snow = snow
        self.source = source
    }

    /// The fallback with the volume `record` names replaced. A record with no data or
    /// an unknown type changes nothing.
    public init(record: ShaderParticleGeometry?) {
        self = .fallback
        guard let record, let data = record.properties else { return }
        switch data.type {
        case 0:
            rain = Self.scale(data, against: .rain)
            rainStreakAspect = Self.aspect(data.particleSize)
        case 1:
            snow = Self.scale(data, against: .snow)
            snowLook = PrecipitationLook(
                texturePath: record.texturePath,
                grid: data.subtextureCount
            )
        default:
            return
        }
        source = record.editorID ?? "\(record.formID)"
    }

    /// Size Y over size X, kept to 1 ... 16 so a broken record still draws a streak.
    public static func aspect(_ size: SIMD2<Float>) -> Float {
        guard size.x > 0, size.y.isFinite, size.x.isFinite else { return 1 }
        return min(max(size.y / size.x, 1), 16)
    }

    /// Ratios to the anchor. Size compares the particle area, so a longer, thinner
    /// streak keeps its weight.
    public static func scale(
        _ data: ShaderParticleGeometry.Properties,
        against anchor: PrecipitationAnchor
    ) -> PrecipitationScale {
        let area = data.particleSize.x * data.particleSize.y
        let anchorArea = anchor.size.x * anchor.size.y
        return PrecipitationScale(
            speed: data.gravityVelocity / anchor.gravity,
            size: (area / anchorArea).squareRoot(),
            density: (data.particleDensity ?? anchor.density) / anchor.density
        )
    }
}

nonisolated extension PrecipitationTuning {
    /// One readout line per volume: each hand-tuned value next to the value in use.
    public var readoutLines: [String] {
        [
            "Source: \(source ?? "fallback")",
            Self.line("Rain", base: PrecipitationBase.rain, scale: rain),
            Self.line("Snow", base: PrecipitationBase.snow, scale: snow),
            "Snow look: " + (snowLook.map { "\($0.texturePath), \($0.columns) x \($0.rows)" }
                ?? "generated")
        ]
    }

    private static func line(
        _ name: String,
        base: PrecipitationBase,
        scale: PrecipitationScale
    ) -> String {
        func pair(_ fallback: Float, _ factor: Float) -> String {
            "\(Int(fallback.rounded())) → \(Int((fallback * factor).rounded()))"
        }
        return "\(name): speed \(pair(base.speed, scale.speed))"
            + " · size \(pair(base.radius, scale.size))"
            + " · density × \(String(format: "%.2f", scale.density))"
    }
}

/// The texture an `SPGD` record names (`ICON`) and its grid of particle cells (`DATA`
/// subtexture count). Each particle draws one cell, picked at random.
nonisolated public struct PrecipitationLook: Equatable, Sendable {
    /// A grid larger than this per side is treated as one cell.
    public static let maximumCells: UInt32 = 16

    public let texturePath: String
    public let columns: Int
    public let rows: Int

    /// Nil without a texture.
    public init?(texturePath: String?, grid: SIMD2<UInt32>) {
        guard let texturePath, !texturePath.isEmpty else { return nil }
        self.texturePath = texturePath
        func cells(_ count: UInt32) -> Int {
            count > 0 && count <= Self.maximumCells ? Int(count) : 1
        }
        columns = cells(grid.x)
        rows = cells(grid.y)
    }

    /// `ICON` names a file below `Data\Textures\`; this is the path below `Data\`.
    public var dataPath: String {
        let lowered = texturePath.lowercased()
        return lowered.hasPrefix("textures\\") || lowered.hasPrefix("textures/")
            ? texturePath : "Textures\\" + texturePath
    }

    /// Each cell as `(u, v, width, height)`, row by row.
    public var cellRects: [SIMD4<Float>] {
        let width = 1 / Float(columns)
        let height = 1 / Float(rows)
        return (0 ..< rows).flatMap { row in
            (0 ..< columns).map { column in
                SIMD4(Float(column) * width, Float(row) * height, width, height)
            }
        }
    }
}
