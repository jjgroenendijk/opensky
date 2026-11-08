// What asset optimisation writes for each texture: the shipped blocks, the smallest
// ASTC format that meets a quality target, or a format forced per texture group.
// docs/engine/asset-cache.md, "Texture quality", has the rules and measurements.

import Foundation

/// Which texture group a shipped texture belongs to, from its file name suffix.
nonisolated public enum AssetTextureClass: UInt8, CaseIterable, Sendable {
    case color
    case normal
    case data

    /// `_n` and `_msn` are normal maps; `_s`, `_g`, `_e`, `_m`, `_p`, `_b`, and
    /// `_sk` are specular, glow, environment, mask, parallax, backlight, and skin
    /// data. Everything else is color.
    public init(path: String) {
        let name = path.lowercased().split(whereSeparator: { $0 == "\\" || $0 == "/" }).last ?? ""
        let stem = name.hasSuffix(".dds") ? name.dropLast(4) : name[...]
        if stem.hasSuffix("_n") || stem.hasSuffix("_msn") {
            self = .normal
        } else if
            ["_s", "_g", "_e", "_em", "_m", "_p", "_b", "_sk"]
                .contains(where: { stem.hasSuffix($0) })
        {
            self = .data
        } else {
            self = .color
        }
    }

    public var title: String {
        switch self {
        case .color: "Colour"
        case .normal: "Normal"
        case .data: "Data"
        }
    }
}

/// The quality a player picks. Original keeps the shipped blocks; the others are
/// targets the smallest passing format must meet.
nonisolated public enum TextureQuality: UInt8, CaseIterable, Sendable, CustomStringConvertible {
    case original = 0
    case high = 1
    case medium = 2
    case low = 3

    public static let `default` = Self.original

    public var title: String {
        switch self {
        case .original: "Original"
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    /// What the player sees, in plain words.
    public var label: String {
        switch self {
        case .original: "Identical"
        case .high: "No visible loss"
        case .medium: "Slightly softer up close"
        case .low: "Softer up close"
        }
    }

    public var description: String {
        title
    }

    /// Nil for Original. The limits come from the base-game sample measurement.
    public var target: TextureQualityTarget? {
        switch self {
        case .original: nil
        case .high: TextureQualityTarget(psnr: 42, normalDegrees: 2, cutoutAlphaPSNR: 46)
        case .medium: TextureQualityTarget(psnr: 38, normalDegrees: 3.5, cutoutAlphaPSNR: 42)
        case .low: TextureQualityTarget(psnr: 34, normalDegrees: 6, cutoutAlphaPSNR: 38)
        }
    }
}

/// The least a converted texture may keep. PSNR is in dB against the source
/// level of the same size; the normal limit is the mean angle in degrees.
nonisolated public struct TextureQualityTarget: Equatable, Sendable {
    public let psnr: Double
    public let normalDegrees: Double
    /// Holes and ragged edges show where cut-out alpha is wrong, so it is stricter.
    public let cutoutAlphaPSNR: Double

    public init(psnr: Double, normalDegrees: Double, cutoutAlphaPSNR: Double) {
        self.psnr = psnr
        self.normalDegrees = normalDegrees
        self.cutoutAlphaPSNR = cutoutAlphaPSNR
    }

    public func isMet(by measure: TextureMeasure, normalMap: Bool, cutoutAlpha: Bool) -> Bool {
        let colour = normalMap
            ? (measure.normalDegrees ?? .infinity) <= normalDegrees
            : measure.rgbPSNR >= psnr
        return colour && measure.alphaPSNR >= (cutoutAlpha ? cutoutAlphaPSNR : psnr)
    }
}

/// How far an encoded level is from its source level.
nonisolated public struct TextureMeasure: Equatable, Sendable {
    public let rgbPSNR: Double
    public let alphaPSNR: Double
    public let normalDegrees: Double?

    public init(rgbPSNR: Double, alphaPSNR: Double, normalDegrees: Double?) {
        self.rgbPSNR = rgbPSNR
        self.alphaPSNR = alphaPSNR
        self.normalDegrees = normalDegrees
    }
}

/// A format forced for one texture group, under "Show details".
nonisolated public enum TextureFormatChoice: UInt8, CaseIterable, Sendable {
    case automatic = 0
    case shipped
    case astc4x4
    case astc5x5
    case astc6x6
    case astc8x8

    public var format: ReadyTextureFormat? {
        switch self {
        case .automatic, .shipped: nil
        case .astc4x4: .astc4x4
        case .astc5x5: .astc5x5
        case .astc6x6: .astc6x6
        case .astc8x8: .astc8x8
        }
    }

    /// `ASTC 6x6, 3.56 bits per pixel`.
    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .shipped: "Shipped"
        default: format.map { "\($0.title), \($0.bitsPerPixelText) bits per pixel" } ?? ""
        }
    }
}

/// What one texture becomes.
nonisolated public enum TexturePlan: Equatable, Sendable {
    case shipped
    case search(TextureQualityTarget)
    case forced(ReadyTextureFormat)
}

nonisolated public struct AssetTextureOutput: Equatable, Sendable {
    public var quality: TextureQuality
    public var formats: [AssetTextureClass: TextureFormatChoice]
    /// The long side a texture keeps at most, by dropping its top levels. Nil keeps all.
    public var maximumSide: Int?

    public init(
        quality: TextureQuality = .default,
        formats: [AssetTextureClass: TextureFormatChoice] = [:],
        maximumSide: Int? = nil
    ) {
        self.quality = quality
        self.formats = formats
        self.maximumSide = maximumSide
    }

    public func plan(forPath path: String) -> TexturePlan {
        let choice = formats[AssetTextureClass(path: path)] ?? .automatic
        switch choice {
        case .automatic:
            return quality.target.map(TexturePlan.search) ?? .shipped
        case .shipped:
            return .shipped
        default:
            return choice.format.map(TexturePlan.forced) ?? .shipped
        }
    }

    /// The byte each texture entry records, so a change marks only the textures
    /// whose output changed: 0 shipped, 1 to 3 a quality target, 16 and up a forced
    /// format. The top three bits hold the size limit as `log2(side) - 7`.
    public func variant(forPath path: String) -> UInt8 {
        let size: UInt8 = maximumSide.map { side -> UInt8 in
            let log2 = Int.bitWidth - 1 - max(side, 1).leadingZeroBitCount
            return UInt8(min(max(log2 - 7, 1), 7)) << 5
        } ?? 0
        switch plan(forPath: path) {
        case .shipped: return size
        case .search: return size | quality.rawValue
        case let .forced(format): return size | 0x10 | (format.rawValue & 0x0F)
        }
    }

    /// True when some texture is re-encoded, which needs a Metal device for the decode.
    public var needsEncoder: Bool {
        quality.target != nil || formats.values.contains { $0.format != nil }
    }
}

nonisolated public enum TextureFormatSearch {
    /// Smallest first, so the first format that meets the target is the smallest.
    public static let order: [ReadyTextureFormat] = [.astc8x8, .astc6x6, .astc5x5, .astc4x4]
    /// A texture this size or smaller keeps its shipped blocks: the saving is too small.
    public static let smallSide = 256

    /// The formats worth trying, smallest first. Never one larger than the shipped format.
    public static func candidates(
        shipped: ReadyTextureFormat, width: Int, height: Int
    ) -> [ReadyTextureFormat] {
        guard max(width, height) > smallSide else { return [] }
        return order.filter { $0.bitsPerPixel < shipped.bitsPerPixel }
    }
}

nonisolated extension TextureFormatSearch {
    /// The first candidate whose measure meets `target`, or nil to keep the shipped
    /// blocks. `measure` encodes and decodes one candidate, so it runs at most once each.
    public static func pick(
        _ candidates: [ReadyTextureFormat],
        target: TextureQualityTarget,
        normalMap: Bool,
        cutoutAlpha: Bool,
        measure: (ReadyTextureFormat) throws -> TextureMeasure
    ) rethrows -> ReadyTextureFormat? {
        for format in candidates {
            let result = try measure(format)
            if target.isMet(by: result, normalMap: normalMap, cutoutAlpha: cutoutAlpha) {
                return format
            }
        }
        return nil
    }
}
