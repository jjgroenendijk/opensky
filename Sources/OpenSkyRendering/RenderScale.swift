// The share of the display size the 3D scene renders at before MetalFX upscales it,
// and the sub-pixel jitter each frame adds. See docs/rendering/upscaling.md.

import simd

/// Which MetalFX scaler rebuilds the full frame. Raw values are setting indexes.
nonisolated public enum UpscalerKind: Int, CaseIterable, Sendable {
    /// Uses earlier frames and motion vectors; also anti-aliases. Costs more GPU time.
    case temporal
    /// Uses the current frame alone; cheap, but keeps the aliasing of the input.
    case spatial

    public init(settingIndex: Int) {
        self = Self(rawValue: settingIndex) ?? .temporal
    }
}

nonisolated public struct RenderScale: Equatable, Sendable {
    /// The choices of the render-scale setting, in percent, in setting-index order.
    /// 0 is off: the scene renders at the display size and nothing upscales.
    public static let percentOptions = [0, 50, 59, 67, 75, 85, 100]
    public static let off = RenderScale(percent: 0)

    /// 0, or 50 through 100. MetalFX upscales at most 2x on each axis on Apple silicon.
    public let percent: Int

    public init(percent: Int) {
        self.percent = percent <= 0 ? 0 : min(max(percent, 50), 100)
    }

    /// The setting stores an index into `percentOptions`.
    public init(settingIndex: Int) {
        let options = Self.percentOptions
        self.init(percent: options[min(max(settingIndex, 0), options.count - 1)])
    }

    public var isOn: Bool {
        percent > 0
    }

    public var settingIndex: Int {
        Self.percentOptions.firstIndex(of: percent) ?? 0
    }

    /// The scene size for an output size, never below one pixel.
    public func inputSize(width: Int, height: Int) -> SIMD2<Int> {
        guard isOn else { return SIMD2(width, height) }
        func scaled(_ value: Int) -> Int {
            max(1, Int((Double(value) * Double(percent) / 100).rounded()))
        }
        return SIMD2(scaled(width), scaled(height))
    }

    /// Frames in one jitter cycle.
    public static let jitterPhases = 8

    /// This frame's sub-pixel offset in input pixels, each axis in -0.5 ..< 0.5. A Halton
    /// sequence in bases 2 and 3 covers the pixel evenly over a few frames.
    public static func jitter(frame: Int) -> SIMD2<Float> {
        let index = frame % jitterPhases + 1
        return SIMD2(halton(index, base: 2), halton(index, base: 3)) - 0.5
    }

    static func halton(_ index: Int, base: Int) -> Float {
        var fraction: Float = 1
        var result: Float = 0
        var remaining = index
        while remaining > 0 {
            fraction /= Float(base)
            result += fraction * Float(remaining % base)
            remaining /= base
        }
        return result
    }

    /// `projection` moved by `jitter` input pixels. Pixel y grows down, clip y up.
    public static func jittered(
        _ projection: float4x4,
        by jitter: SIMD2<Float>,
        inputSize: SIMD2<Int>
    ) -> float4x4 {
        var shift = matrix_identity_float4x4
        shift.columns.3.x = 2 * jitter.x / Float(inputSize.x)
        shift.columns.3.y = -2 * jitter.y / Float(inputSize.y)
        return shift * projection
    }
}
