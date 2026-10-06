// Writes an RGBA8 image as an uncompressed DDS with a box-filtered mip chain,
// so a texture painted on the CPU loads through the normal texture path.
// Layout: docs/formats/dds.md, "CPU decode".

import Foundation
import OpenSkyFormatsCore

nonisolated public enum DDSEncoder {
    public static func rgba8888(_ image: DecodedImage) -> Data {
        let levels = mipChain(image)
        var writer = BinaryWriter()
        writer.write(Data("DDS ".utf8))
        // DDSD_CAPS, HEIGHT, WIDTH, PITCH, PIXELFORMAT, MIPMAPCOUNT.
        for value: UInt32 in [124, 0x0002_100F, UInt32(image.height), UInt32(image.width)] {
            writer.writeUInt32(value)
        }
        writer.writeUInt32(UInt32(image.width * 4))
        writer.writeUInt32(0)
        writer.writeUInt32(UInt32(levels.count))
        (0 ..< 11).forEach { _ in writer.writeUInt32(0) }
        // DDS_PIXELFORMAT: RGB with alpha, 32 bits, R in the low byte.
        for value: UInt32 in [32, 0x41, 0, 32, 0xFF, 0xFF00, 0xFF0000, 0xFF00_0000] {
            writer.writeUInt32(value)
        }
        // DDSCAPS_COMPLEX, TEXTURE, MIPMAP.
        for value: UInt32 in [0x0040_1008, 0, 0, 0, 0] {
            writer.writeUInt32(value)
        }
        levels.forEach { writer.write(Data($0.rgba)) }
        return writer.data
    }

    static func mipChain(_ image: DecodedImage) -> [DecodedImage] {
        var levels = [image]
        while let last = levels.last, last.width > 1 || last.height > 1 {
            levels.append(halved(last))
        }
        return levels
    }

    private static func halved(_ image: DecodedImage) -> DecodedImage {
        let width = max(1, image.width / 2)
        let height = max(1, image.height / 2)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0 ..< height {
            for column in 0 ..< width {
                for channel in 0 ..< 4 {
                    var sum = 0
                    for (dy, dx) in [(0, 0), (0, 1), (1, 0), (1, 1)] {
                        let sourceRow = min(row * 2 + dy, image.height - 1)
                        let sourceColumn = min(column * 2 + dx, image.width - 1)
                        sum +=
                            Int(image.rgba[(sourceRow * image.width + sourceColumn) * 4 + channel])
                    }
                    rgba[(row * width + column) * 4 + channel] = UInt8(sum / 4)
                }
            }
        }
        return DecodedImage(width: width, height: height, rgba: rgba)
    }
}
