// Writes an RGBA8 image as an uncompressed DDS with a box-filtered mip chain,
// so a texture painted on the CPU loads through the normal texture path.
// Layout: docs/formats/dds.md, "CPU decode".

import Foundation
import OpenSkyFormatsCore
import OpenSkyImageKernels

nonisolated public enum DDSEncoder {
    public static func rgba8888(_ image: DecodedImage) -> Data {
        let levels = ImageMips.chain(image)
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
}
