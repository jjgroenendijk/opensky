// A picture of where two same-size images differ, for a reader to look at beside the
// PSNR from `TextureImageDifference`.

import Foundation

nonisolated extension TexturePixels {
    /// Each RGB channel is the absolute difference times `gain`, capped at 255; alpha is opaque.
    public static func difference(
        reference: TexturePixels, candidate: TexturePixels, gain: Int = 4
    ) throws -> TexturePixels {
        guard
            reference.width == candidate.width, reference.height == candidate.height,
            reference.rgba.count == candidate.rgba.count
        else {
            throw TextureImageDifferenceError.sizeMismatch(
                reference: [reference.width, reference.height],
                candidate: [candidate.width, candidate.height]
            )
        }
        var output = [UInt8](repeating: 255, count: reference.rgba.count)
        for index in reference.rgba.indices where index % 4 != 3 {
            let delta = abs(Int(reference.rgba[index]) - Int(candidate.rgba[index]))
            output[index] = UInt8(min(255, delta * gain))
        }
        return TexturePixels(width: reference.width, height: reference.height, rgba: output)
    }
}
