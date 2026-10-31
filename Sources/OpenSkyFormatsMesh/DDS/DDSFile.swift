// DDS texture container: magic, DDS_HEADER, optional DXT10 header, then the
// mip chain. Reads 2D BC1-BC5/BC7, 32-bit RGB, 24-bit RGB, and 8-bit luminance, and
// cubemaps and volumes when the caller asks; arrays throw `unsupported`.
// Layout: docs/formats/dds.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public enum DDSError: Error, Equatable, Sendable {
    /// Input violates the documented layout.
    case malformed(String)
    /// Valid DDS, but a variant OpenSky does not read (array, unsupported
    /// pixel format), or a cubemap or volume the caller did not ask for.
    case unsupported(String)
}

/// Texture formats OpenSky reads. Raw values match the closest DXGI_FORMAT
/// UNORM code (dxgiformat.h) so probes print recognizable numbers.
nonisolated public enum DDSPixelFormat: UInt32, Sendable {
    case bc1 = 71 // DXGI_FORMAT_BC1_UNORM, FourCC "DXT1"
    case bc2 = 74 // DXGI_FORMAT_BC2_UNORM, FourCC "DXT3"
    case bc3 = 77 // DXGI_FORMAT_BC3_UNORM, FourCC "DXT5"
    case bc4 = 80 // DXGI_FORMAT_BC4_UNORM, FourCC "ATI1"/"BC4U"
    case bc5 = 83 // DXGI_FORMAT_BC5_UNORM, FourCC "ATI2"/"BC5U"
    case rgba8888 = 28 // DXGI_FORMAT_R8G8B8A8_UNORM, legacy DDPF_RGB header
    case bgra8888 = 87 // DXGI_FORMAT_B8G8R8A8_UNORM, legacy DDPF_RGB header
    case xrgb8888 = 88 // DXGI_FORMAT_B8G8R8X8_UNORM, legacy DDPF_RGB header
    case bc7 = 98 // DXGI_FORMAT_BC7_UNORM, DX10 header only

    public var isBlockCompressed: Bool {
        switch self {
        case .rgba8888, .bgra8888, .xrgb8888: false
        default: true
        }
    }

    /// Texel width/height represented by one payload block.
    public var blockDimension: Int {
        isBlockCompressed ? 4 : 1
    }

    /// Bytes per block: 4x4 for BCn, 1x1 for 32-bit RGB.
    public var bytesPerBlock: Int {
        switch self {
        case .bc1, .bc4: 8
        case .bc2, .bc3, .bc5, .bc7: 16
        case .rgba8888, .bgra8888, .xrgb8888: 4
        }
    }
}

/// Parsed 2D texture: dimensions, format, and a byte range per mip level.
nonisolated public struct DDSFile: Sendable {
    private enum Layout {
        static let magic: FourCC = "DDS "
        static let headerSize: UInt32 = 124
        static let pixelFormatSize: UInt32 = 32
        /// DDS_HEADER.dwFlags
        static let flagMipMapCount: UInt32 = 0x20000 // DDSD_MIPMAPCOUNT
        static let flagPitch: UInt32 = 0x8 // DDSD_PITCH
        static let flagLinearSize: UInt32 = 0x80000 // DDSD_LINEARSIZE
        /// DDS_PIXELFORMAT.dwFlags
        static let flagFourCC: UInt32 = 0x4 // DDPF_FOURCC
        static let flagAlphaPixels: UInt32 = 0x1 // DDPF_ALPHAPIXELS
        static let flagRGB: UInt32 = 0x40 // DDPF_RGB
        static let flagLuminance: UInt32 = 0x20000 // DDPF_LUMINANCE
        static let luminanceBitCount: UInt32 = 8
        static let luminanceMask: UInt32 = 0xFF
        static let xrgbBitCount: UInt32 = 32
        static let rgb24BitCount: UInt32 = 24
        /// One channel mask per byte of a 24-bit texel, in file order.
        static let rgb24ByteMasks: [UInt32] = [0x0000_00FF, 0x0000_FF00, 0x00FF_0000]
        static let xrgbRedMask: UInt32 = 0x00FF_0000
        static let xrgbGreenMask: UInt32 = 0x0000_FF00
        static let xrgbBlueMask: UInt32 = 0x0000_00FF
        static let xrgbAlphaMask: UInt32 = 0
        static let rgbaRedMask: UInt32 = 0x0000_00FF
        static let rgbaGreenMask: UInt32 = 0x0000_FF00
        static let rgbaBlueMask: UInt32 = 0x00FF_0000
        static let rgbaAlphaMask: UInt32 = 0xFF00_0000
        static let bgraRedMask: UInt32 = 0x00FF_0000
        static let bgraGreenMask: UInt32 = 0x0000_FF00
        static let bgraBlueMask: UInt32 = 0x0000_00FF
        static let bgraAlphaMask: UInt32 = 0xFF00_0000
        // DDS_HEADER.dwCaps2
        static let capsCubemap: UInt32 = 0x200 // DDSCAPS2_CUBEMAP
        static let capsAllFaces: UInt32 = 0xFC00 // DDSCAPS2_CUBEMAP_POSITIVEX ... NEGATIVEZ
        static let capsVolume: UInt32 = 0x200000 // DDSCAPS2_VOLUME
        // DDS_HEADER_DXT10
        static let dimensionTexture2D: UInt32 = 3 // D3D10_RESOURCE_DIMENSION
        static let dimensionTexture3D: UInt32 = 4
        static let miscTextureCube: UInt32 = 0x4 // D3D10_RESOURCE_MISC
        /// Sanity bound; largest vanilla SSE textures are 8192 (2.5 probe).
        static let maxDimension = 16384
    }

    private struct PixelFormatHeader {
        let flags: UInt32
        let fourCC: FourCC
        let bitCount: UInt32
        let redMask: UInt32
        let greenMask: UInt32
        let blueMask: UInt32
        let alphaMask: UInt32
    }

    /// How uncompressed texels sit in the file. 24-bit texels widen to the
    /// 4-byte `xrgb8888` layout on read, because Metal has no 24-bit format.
    private enum TexelPacking: Equatable {
        case native
        /// Byte position of red, green, and blue inside one 3-byte texel.
        case rgb24(red: Int, green: Int, blue: Int)
        /// One grey byte per texel, read as R = G = B.
        case luminance8

        var bytesPerTexel: Int? {
            switch self {
            case .native: nil
            case .rgb24: 3
            case .luminance8: 1
            }
        }
    }

    private struct Header {
        let flags: UInt32
        let width: Int
        let height: Int
        /// dwDepth counts only for a volume; some 2D files leave junk there.
        let declaredDepth: Int
        let pitchOrLinearSize: UInt32
        let mipCount: Int
        let pixelFormat: PixelFormatHeader
        let isCubemap: Bool
        var isVolume: Bool

        var depth: Int {
            isVolume ? declaredDepth : 1
        }
    }

    public let width: Int
    public let height: Int
    /// Slices of a volume texture; 1 for a 2D texture or a cubemap.
    public let depth: Int
    public let mipCount: Int
    public let format: DDSPixelFormat
    /// DX10 header carried an `_SRGB` DXGI format. Advisory: the renderer
    /// picks color space per usage (diffuse sRGB, normal/data linear).
    public let declaresSRGB: Bool
    /// 6 for a cubemap, in the order +X, -X, +Y, -Y, +Z, -Z; 1 otherwise.
    public let faceCount: Int

    private let data: Data
    private let packing: TexelPacking
    /// Byte range of each mip level within `data`, largest level first, per face.
    private let faceMipRanges: [[Range<Int>]]

    /// A cubemap or a volume throws `unsupported` unless the caller allows it.
    public init(data: Data, allowsCubemap: Bool = false, allowsVolume: Bool = false) throws {
        self.data = data
        var reader = BinaryReader(data)
        var header = try Self.readHeader(reader: &reader)
        width = header.width
        height = header.height
        var isCubemap = header.isCubemap

        if header.pixelFormat.flags & Layout.flagFourCC != 0 {
            let resolved = try Self.resolveFormat(
                fourCC: header.pixelFormat.fourCC,
                reader: &reader
            )
            (format, declaresSRGB) = (resolved.format, resolved.sRGB)
            isCubemap = isCubemap || resolved.isCubemap
            header.isVolume = header.isVolume || resolved.isVolume
            packing = .native
        } else if header.pixelFormat.flags & Layout.flagLuminance != 0 {
            (format, packing) = try (Self.resolveLuminance(header: header), .luminance8)
            declaresSRGB = false
        } else {
            // DDS_PIXELFORMAT defines channel masks over the little-endian pixel
            // word. Masks identify on-disk channel order; no host byte-order
            // assumption enters mip slicing. Microsoft DDS_PIXELFORMAT:
            // https://learn.microsoft.com/en-us/windows/win32/direct3ddds/dds-pixelformat
            (format, packing) = try header.pixelFormat.bitCount == Layout.rgb24BitCount
                ? Self.resolveRGB24(header: header)
                : (Self.resolveUncompressedFormat(header: header), .native)
            declaresSRGB = false
        }

        guard !header.isVolume || allowsVolume else {
            throw DDSError.unsupported("volume texture")
        }
        guard (1 ... Layout.maxDimension).contains(header.depth) else {
            throw DDSError.malformed("volume depth \(header.depth) out of range")
        }
        depth = header.depth

        // DDSD_MIPMAPCOUNT absent -> single level, whatever dwMipMapCount says.
        let claimedMips = header.flags & Layout.flagMipMapCount != 0
            ? max(1, header.mipCount) : 1
        let fullChain = Int.bitWidth - max(width, height, header.depth).leadingZeroBitCount
        guard claimedMips <= fullChain else {
            throw DDSError.malformed("mip count \(claimedMips) exceeds full chain \(fullChain)")
        }
        mipCount = claimedMips
        guard !(header.isVolume && isCubemap) else {
            throw DDSError.malformed("volume texture marked as a cubemap")
        }
        guard !isCubemap || allowsCubemap else { throw DDSError.unsupported("cubemap") }
        guard !isCubemap || width == height else {
            throw DDSError.malformed("cubemap faces \(width)x\(height) are not square")
        }
        faceCount = isCubemap ? 6 : 1

        var faces: [[Range<Int>]] = []
        var start = reader.offset
        for _ in 0 ..< faceCount {
            let ranges = try Self.mipRanges(
                header: header,
                mipCount: mipCount,
                bytesPerBlock: packing.bytesPerTexel ?? format.bytesPerBlock,
                blockDimension: format.blockDimension,
                bytes: start ..< data.count
            )
            faces.append(ranges)
            start = ranges.last?.upperBound ?? start
        }
        faceMipRanges = faces
    }

    private static func readHeader(reader: inout BinaryReader) throws -> Header {
        guard try reader.readFourCC() == Layout.magic else {
            throw DDSError.malformed("bad magic (expected \"DDS \")")
        }
        guard try reader.readUInt32() == Layout.headerSize else {
            throw DDSError.malformed("DDS_HEADER.dwSize != 124")
        }
        let flags = try reader.readUInt32()
        let height = try Int(reader.readUInt32())
        let width = try Int(reader.readUInt32())
        let pitchOrLinearSize = try reader.readUInt32()
        let declaredDepth = try Int(reader.readUInt32())
        let mipCount = try Int(reader.readUInt32())
        reader.skip(11 * 4) // dwReserved1

        guard
            (1 ... Layout.maxDimension).contains(width),
            (1 ... Layout.maxDimension).contains(height)
        else {
            throw DDSError.malformed("dimensions \(width)x\(height) out of range")
        }

        let pixelFormat = try readPixelFormat(reader: &reader)
        reader.skip(4) // dwCaps
        let caps2 = try reader.readUInt32()
        reader.skip(3 * 4) // dwCaps3, dwCaps4, dwReserved2
        let isCubemap = caps2 & Layout.capsCubemap != 0
        if isCubemap, caps2 & Layout.capsAllFaces != Layout.capsAllFaces {
            throw DDSError.unsupported("cubemap without all six faces")
        }
        return Header(
            flags: flags,
            width: width,
            height: height,
            declaredDepth: declaredDepth,
            pitchOrLinearSize: pitchOrLinearSize,
            mipCount: mipCount,
            pixelFormat: pixelFormat,
            isCubemap: isCubemap,
            isVolume: caps2 & Layout.capsVolume != 0
        )
    }

    private static func readPixelFormat(reader: inout BinaryReader) throws -> PixelFormatHeader {
        guard try reader.readUInt32() == Layout.pixelFormatSize else {
            throw DDSError.malformed("DDS_PIXELFORMAT.dwSize != 32")
        }
        return try PixelFormatHeader(
            flags: reader.readUInt32(),
            fourCC: reader.readFourCC(),
            bitCount: reader.readUInt32(),
            redMask: reader.readUInt32(),
            greenMask: reader.readUInt32(),
            blueMask: reader.readUInt32(),
            alphaMask: reader.readUInt32()
        )
    }
}

nonisolated extension DDSFile {
    private static func resolveUncompressedFormat(header: Header) throws -> DDSPixelFormat {
        let pixelFormat = header.pixelFormat
        let xrgbFlags = Layout.flagRGB
        let rgbaFlags = Layout.flagRGB | Layout.flagAlphaPixels
        guard pixelFormat.flags == xrgbFlags || pixelFormat.flags == rgbaFlags else {
            throw DDSError.unsupported(
                "uncompressed pixel flags 0x\(String(pixelFormat.flags, radix: 16))"
            )
        }
        guard pixelFormat.bitCount == Layout.xrgbBitCount else {
            throw DDSError.unsupported("uncompressed RGB bit count \(pixelFormat.bitCount)")
        }
        let isXRGB = pixelFormat.flags == xrgbFlags
            && pixelFormat.redMask == Layout.xrgbRedMask
            && pixelFormat.greenMask == Layout.xrgbGreenMask
            && pixelFormat.blueMask == Layout.xrgbBlueMask
            && pixelFormat.alphaMask == Layout.xrgbAlphaMask
        let isRGBA = pixelFormat.flags == rgbaFlags
            && pixelFormat.redMask == Layout.rgbaRedMask
            && pixelFormat.greenMask == Layout.rgbaGreenMask
            && pixelFormat.blueMask == Layout.rgbaBlueMask
            && pixelFormat.alphaMask == Layout.rgbaAlphaMask
        let isBGRA = pixelFormat.flags == rgbaFlags
            && pixelFormat.redMask == Layout.bgraRedMask
            && pixelFormat.greenMask == Layout.bgraGreenMask
            && pixelFormat.blueMask == Layout.bgraBlueMask
            && pixelFormat.alphaMask == Layout.bgraAlphaMask
        guard isXRGB || isRGBA || isBGRA else {
            throw DDSError.unsupported("uncompressed RGB channel masks")
        }

        try checkSizeField(header: header, bytesPerTexel: 4)
        if isXRGB {
            return .xrgb8888
        }
        return isBGRA ? .bgra8888 : .rgba8888
    }

    /// Rows are unpadded, so the declared top-level size must match the texel
    /// size. Some vanilla files set `DDSD_LINEARSIZE` instead of `DDSD_PITCH`.
    private static func checkSizeField(header: Header, bytesPerTexel: UInt32) throws {
        let pitch = UInt32(header.width) * bytesPerTexel
        let declared = header.pitchOrLinearSize
        let expected: UInt32? = if header.flags & Layout.flagPitch != 0 {
            pitch
        } else if header.flags & Layout.flagLinearSize != 0 {
            pitch * UInt32(header.height)
        } else {
            nil
        }
        if let expected, declared != expected {
            throw DDSError.malformed("uncompressed pitch \(declared) != expected \(expected)")
        }
    }

    /// Legacy 8-bit `DDPF_LUMINANCE`, used by the effect noise volume. Each texel
    /// widens to `xrgb8888` grey, the way Direct3D samples L8.
    private static func resolveLuminance(header: Header) throws -> DDSPixelFormat {
        let pixelFormat = header.pixelFormat
        guard
            pixelFormat.flags == Layout.flagLuminance,
            pixelFormat.bitCount == Layout.luminanceBitCount,
            pixelFormat.redMask == Layout.luminanceMask
        else {
            throw DDSError.unsupported(
                "luminance flags 0x\(String(pixelFormat.flags, radix: 16)), "
                    + "bit count \(pixelFormat.bitCount)"
            )
        }
        try checkSizeField(header: header, bytesPerTexel: 1)
        return .xrgb8888
    }

    /// Legacy 24-bit `DDPF_RGB`, used by the tint masks.
    private static func resolveRGB24(header: Header) throws -> (DDSPixelFormat, TexelPacking) {
        let pixelFormat = header.pixelFormat
        guard pixelFormat.flags == Layout.flagRGB, pixelFormat.alphaMask == 0 else {
            throw DDSError.unsupported(
                "24-bit RGB pixel flags 0x\(String(pixelFormat.flags, radix: 16))"
            )
        }
        let positions = [pixelFormat.redMask, pixelFormat.greenMask, pixelFormat.blueMask]
            .map { Layout.rgb24ByteMasks.firstIndex(of: $0) }
        guard
            let red = positions[0], let green = positions[1], let blue = positions[2],
            Set([red, green, blue]).count == 3
        else {
            throw DDSError.unsupported("24-bit RGB channel masks")
        }
        try checkSizeField(header: header, bytesPerTexel: 3)
        return (.xrgb8888, .rgb24(red: red, green: green, blue: blue))
    }

    private struct ResolvedFormat {
        let format: DDSPixelFormat
        let sRGB: Bool
        let isCubemap: Bool
        let isVolume: Bool
    }

    /// FourCC -> format; "DX10" pulls the format out of DDS_HEADER_DXT10 and
    /// rejects 1D resources.
    private static func resolveFormat(
        fourCC: FourCC,
        reader: inout BinaryReader
    ) throws -> ResolvedFormat {
        guard fourCC == "DX10" else {
            return try ResolvedFormat(
                format: resolveLegacyFormat(fourCC),
                sRGB: false,
                isCubemap: false,
                isVolume: false
            )
        }

        // DDS_HEADER_DXT10 (20 bytes). sRGB DXGI codes are UNORM + 1.
        let dxgiFormat = try reader.readUInt32()
        let dimension = try reader.readUInt32()
        let miscFlag = try reader.readUInt32()
        let arraySize = try reader.readUInt32()
        reader.skip(4) // miscFlags2 (alpha mode)

        guard dimension == Layout.dimensionTexture2D || dimension == Layout.dimensionTexture3D
        else {
            throw DDSError.unsupported("resource dimension \(dimension)")
        }
        guard arraySize <= 1 else {
            throw DDSError.unsupported("texture array of \(arraySize)")
        }
        let (format, sRGB) = try resolveDXGIFormat(dxgiFormat)
        return ResolvedFormat(
            format: format, sRGB: sRGB, isCubemap: miscFlag & Layout.miscTextureCube != 0,
            isVolume: dimension == Layout.dimensionTexture3D
        )
    }

    private static func resolveLegacyFormat(_ fourCC: FourCC) throws -> DDSPixelFormat {
        switch fourCC {
        case "DXT1": .bc1
        case "DXT3": .bc2
        case "DXT5": .bc3
        case "ATI1", "BC4U": .bc4
        case "ATI2", "BC5U": .bc5
        default:
            throw DDSError.unsupported("FourCC \(fourCC)")
        }
    }

    private static func resolveDXGIFormat(
        _ dxgiFormat: UInt32
    ) throws -> (DDSPixelFormat, sRGB: Bool) {
        switch dxgiFormat {
        case DDSPixelFormat.bc1.rawValue: (.bc1, false)
        case DDSPixelFormat.bc2.rawValue: (.bc2, false)
        case DDSPixelFormat.bc3.rawValue: (.bc3, false)
        case DDSPixelFormat.bc4.rawValue: (.bc4, false)
        case DDSPixelFormat.bc5.rawValue: (.bc5, false)
        case DDSPixelFormat.bc7.rawValue: (.bc7, false)
        // BC1/2/3/7 _SRGB codes are UNORM + 1; 81/84 are BC4/BC5 _SNORM.
        case DDSPixelFormat.bc1.rawValue + 1: (.bc1, true)
        case DDSPixelFormat.bc2.rawValue + 1: (.bc2, true)
        case DDSPixelFormat.bc3.rawValue + 1: (.bc3, true)
        case DDSPixelFormat.bc7.rawValue + 1: (.bc7, true)
        default: throw DDSError.unsupported("DXGI format \(dxgiFormat)")
        }
    }

    /// Tightly packed chain inside `bytes` (payload start ..< file end): each
    /// level is ceil(w/4) * ceil(h/4) blocks per slice, and a volume level holds
    /// all its slices (DDS guide block-size math).
    private static func mipRanges(
        header: Header,
        mipCount: Int,
        bytesPerBlock: Int,
        blockDimension: Int,
        bytes: Range<Int>
    ) throws -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var offset = bytes.lowerBound
        for level in 0 ..< mipCount {
            let blocksWide = (max(1, header.width >> level) + blockDimension - 1) / blockDimension
            let blocksHigh = (max(1, header.height >> level) + blockDimension - 1) / blockDimension
            let slices = max(1, header.depth >> level)
            let size = blocksWide * blocksHigh * bytesPerBlock * slices
            guard offset + size <= bytes.upperBound else {
                throw DDSError.malformed(
                    "mip \(level) needs \(size) bytes at \(offset), "
                        + "file ends at \(bytes.upperBound)"
                )
            }
            ranges.append(offset ..< offset + size)
            offset += size
        }
        return ranges
    }
}

nonisolated extension DDSFile {
    public func width(level: Int) -> Int {
        max(1, width >> level)
    }

    public func height(level: Int) -> Int {
        max(1, height >> level)
    }

    public func depth(level: Int) -> Int {
        max(1, depth >> level)
    }

    /// Payload bytes of one mip level of one face, in the layout `format` names.
    /// A volume level holds `depth(level:)` slices, front to back.
    public func mipData(level: Int, face: Int = 0) -> Data {
        let range = faceMipRanges[face][level]
        let stored = data.subdata(
            in: (data.startIndex + range.lowerBound) ..< (data.startIndex + range.upperBound)
        )
        switch packing {
        case .native: return stored
        case let .rgb24(red, green, blue):
            return Self.widenRGB24(stored, channels: [blue, green, red])
        case .luminance8: return Self.widenLuminance(stored)
        }
    }

    /// 1-byte grey to L, L, L, 255.
    private static func widenLuminance(_ stored: Data) -> Data {
        var out = Data(repeating: 255, count: stored.count * 4)
        stored.withUnsafeBytes { source in
            out.withUnsafeMutableBytes { target in
                for (texel, grey) in source.enumerated() {
                    target[texel * 4] = grey
                    target[texel * 4 + 1] = grey
                    target[texel * 4 + 2] = grey
                }
            }
        }
        return out
    }

    /// 3-byte texels to B, G, R, 255, the `xrgb8888` byte order.
    private static func widenRGB24(_ stored: Data, channels: [Int]) -> Data {
        let texelCount = stored.count / 3
        var out = Data(repeating: 255, count: texelCount * 4)
        stored.withUnsafeBytes { source in
            out.withUnsafeMutableBytes { target in
                for texel in 0 ..< texelCount {
                    for (slot, channel) in channels.enumerated() {
                        target[texel * 4 + slot] = source[texel * 3 + channel]
                    }
                }
            }
        }
        return out
    }

    /// Bytes per row — `MTLTexture.replace` stride.
    public func bytesPerRow(level: Int) -> Int {
        let blockDimension = format.blockDimension
        return (width(level: level) + blockDimension - 1) / blockDimension
            * format.bytesPerBlock
    }

    /// Bytes per volume slice — `MTLTexture.replace` image stride.
    public func bytesPerImage(level: Int) -> Int {
        let blockDimension = format.blockDimension
        return (height(level: level) + blockDimension - 1) / blockDimension
            * bytesPerRow(level: level)
    }
}
