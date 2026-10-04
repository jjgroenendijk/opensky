// Paints race tint layers (skin tone, war paint, dirt) over a face color map on
// the CPU. Each mask is one byte per pixel; see docs/engine/race-menu.md.

import Foundation

nonisolated public struct ChargenTintLayer: Equatable, Sendable {
    /// One coverage byte per pixel, the same size as the base picture.
    public let mask: [UInt8]
    public let color: SIMD4<UInt8>
    /// 0 to 1.
    public let strength: Float

    public init(mask: [UInt8], color: SIMD4<UInt8>, strength: Float) {
        self.mask = mask
        self.color = color
        self.strength = strength
    }
}

nonisolated public enum ChargenTints {
    /// Layers paint in order over `rgba`, a straight alpha blend per pixel. A layer
    /// whose mask size differs is skipped, so a bad mask cannot crash the build.
    public static func paint(rgba: [UInt8], layers: [ChargenTintLayer]) -> [UInt8] {
        var result = rgba
        let pixels = rgba.count / 4
        for layer in layers where layer.mask.count == pixels {
            let strength = min(max(layer.strength, 0), 1)
            let alpha = Float(layer.color.w) / 255
            for pixel in 0 ..< pixels {
                let cover = Float(layer.mask[pixel]) / 255 * strength * alpha
                guard cover > 0 else { continue }
                for channel in 0 ..< 3 {
                    let index = pixel * 4 + channel
                    let blended = Float(result[index]) * (1 - cover)
                        + Float(layer.color[channel]) * cover
                    result[index] = UInt8(min(max(blended.rounded(), 0), 255))
                }
            }
        }
        return result
    }
}
