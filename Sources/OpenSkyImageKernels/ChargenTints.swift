// Paints race tint layers (skin tone, war paint, dirt) over a face color map on
// the CPU. Each mask is one byte per pixel; see docs/engine/race-menu.md.

nonisolated public struct ChargenTintLayer: Equatable, Sendable {
    /// One coverage byte per pixel, the same size as the base picture.
    public let mask: [UInt8]
    /// `TINC`; the fourth byte is 0 in every vanilla NPC, so it is not read.
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
            for pixel in 0 ..< pixels {
                let cover = Float(layer.mask[pixel]) / 255 * strength
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

    /// One coverage byte per texel from a mask picture's red channel, scaled to
    /// `width` x `height` by nearest texel; the masks are smaller than the face.
    public static func coverage(
        rgba: [UInt8], width: Int, height: Int, toWidth: Int, toHeight: Int
    ) -> [UInt8] {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else {
            return [UInt8](repeating: 0, count: toWidth * toHeight)
        }
        var mask = [UInt8](repeating: 0, count: toWidth * toHeight)
        for row in 0 ..< toHeight {
            let sourceRow = row * height / toHeight
            for column in 0 ..< toWidth {
                let sourceColumn = column * width / toWidth
                mask[row * toWidth + column] = rgba[(sourceRow * width + sourceColumn) * 4]
            }
        }
        return mask
    }
}
