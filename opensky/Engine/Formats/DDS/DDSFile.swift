// DDS (DirectDraw Surface) texture container for Skyrim SE textures:
// magic, DDS_HEADER, optional DDS_HEADER_DXT10, then a tightly packed mip
// chain. Reads 2D BC1-BC5/BC7 plus legacy 32-bit xRGB8888/RGBA8888/BGRA8888;
// cubemaps, volumes and arrays throw `unsupported`.
//
// Reference: Microsoft DDS programming guide
//   https://learn.microsoft.com/en-us/windows/win32/direct3ddds/dx-graphics-dds-pguide
//   (DDS_HEADER, DDS_PIXELFORMAT, DDS_HEADER_DXT10 struct pages)
// Layout documented in docs/formats/dds.md.

import Foundation

nonisolated enum DDSError: Error, Equatable {
    /// Input violates the documented layout.
    case malformed(String)
    /// Valid DDS, but a variant OpenSky does not read (cubemap, volume,
    /// array, unsupported pixel format).
    case unsupported(String)
}

/// Texture formats OpenSky reads. Raw values match the closest DXGI_FORMAT
/// UNORM code (dxgiformat.h) so probes print recognizable numbers.
nonisolated enum DDSPixelFormat: UInt32 {
    case bc1 = 71 // DXGI_FORMAT_BC1_UNORM, FourCC "DXT1"
    case bc2 = 74 // DXGI_FORMAT_BC2_UNORM, FourCC "DXT3"
    case bc3 = 77 // DXGI_FORMAT_BC3_UNORM, FourCC "DXT5"
    case bc4 = 80 // DXGI_FORMAT_BC4_UNORM, FourCC "ATI1"/"BC4U"
    case bc5 = 83 // DXGI_FORMAT_BC5_UNORM, FourCC "ATI2"/"BC5U"
    case rgba8888 = 28 // DXGI_FORMAT_R8G8B8A8_UNORM, legacy DDPF_RGB header
    case bgra8888 = 87 // DXGI_FORMAT_B8G8R8A8_UNORM, legacy DDPF_RGB header
    case xrgb8888 = 88 // DXGI_FORMAT_B8G8R8X8_UNORM, legacy DDPF_RGB header
    case bc7 = 98 // DXGI_FORMAT_BC7_UNORM, DX10 header only

    var isBlockCompressed: Bool {
        switch self {
        case .rgba8888, .bgra8888, .xrgb8888: false
        default: true
        }
    }

    /// Texel width/height represented by one payload block.
    var blockDimension: Int {
        isBlockCompressed ? 4 : 1
    }

    /// Bytes per block: 4x4 for BCn, 1x1 for 32-bit RGB.
    var bytesPerBlock: Int {
        switch self {
        case .bc1, .bc4: 8
        case .bc2, .bc3, .bc5, .bc7: 16
        case .rgba8888, .bgra8888, .xrgb8888: 4
        }
    }
}

/// Parsed 2D texture: dimensions, format, and a byte range per mip level.
nonisolated struct DDSFile {
    private enum Layout {
        static let magic: FourCC = "DDS "
        static let headerSize: UInt32 = 124
        static let pixelFormatSize: UInt32 = 32
        /// DDS_HEADER.dwFlags
        static let flagMipMapCount: UInt32 = 0x20000 // DDSD_MIPMAPCOUNT
        static let flagPitch: UInt32 = 0x8 // DDSD_PITCH
        /// DDS_PIXELFORMAT.dwFlags
        static let flagFourCC: UInt32 = 0x4 // DDPF_FOURCC
        static let flagAlphaPixels: UInt32 = 0x1 // DDPF_ALPHAPIXELS
        static let flagRGB: UInt32 = 0x40 // DDPF_RGB
        static let xrgbBitCount: UInt32 = 32
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
        static let capsVolume: UInt32 = 0x200000 // DDSCAPS2_VOLUME
        // DDS_HEADER_DXT10
        static let dimensionTexture2D: UInt32 = 3 // D3D10_RESOURCE_DIMENSION
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

    private struct Header {
        let flags: UInt32
        let width: Int
        let height: Int
        let pitchOrLinearSize: UInt32
        let mipCount: Int
        let pixelFormat: PixelFormatHeader
    }

    let width: Int
    let height: Int
    let mipCount: Int
    let format: DDSPixelFormat
    /// DX10 header carried an `_SRGB` DXGI format. Advisory: the renderer
    /// picks color space per usage (diffuse sRGB, normal/data linear).
    let declaresSRGB: Bool

    private let data: Data
    /// Byte range of each mip level within `data`, largest level first.
    private let mipRanges: [Range<Int>]

    init(data: Data) throws {
        self.data = data
        var reader = BinaryReader(data)
        let header = try Self.readHeader(reader: &reader)
        width = header.width
        height = header.height

        if header.pixelFormat.flags & Layout.flagFourCC != 0 {
            (format, declaresSRGB) = try Self.resolveFormat(
                fourCC: header.pixelFormat.fourCC,
                reader: &reader
            )
        } else {
            // DDS_PIXELFORMAT defines channel masks over the little-endian pixel
            // word. Masks identify on-disk channel order; no host byte-order
            // assumption enters mip slicing. Microsoft DDS_PIXELFORMAT:
            // https://learn.microsoft.com/en-us/windows/win32/direct3ddds/dds-pixelformat
            format = try Self.resolveUncompressedFormat(header: header)
            declaresSRGB = false
        }

        // DDSD_MIPMAPCOUNT absent -> single level, whatever dwMipMapCount says.
        let claimedMips = header.flags & Layout.flagMipMapCount != 0
            ? max(1, header.mipCount) : 1
        let fullChain = Int.bitWidth - max(width, height).leadingZeroBitCount
        guard claimedMips <= fullChain else {
            throw DDSError.malformed("mip count \(claimedMips) exceeds full chain \(fullChain)")
        }
        mipCount = claimedMips

        mipRanges = try Self.mipRanges(
            width: width,
            height: height,
            mipCount: mipCount,
            format: format,
            bytes: reader.offset ..< data.count
        )
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
        reader.skip(4) // dwDepth — volumes rejected below via caps2
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
        if caps2 & Layout.capsCubemap != 0 {
            throw DDSError.unsupported("cubemap")
        }
        if caps2 & Layout.capsVolume != 0 {
            throw DDSError.unsupported("volume texture")
        }
        return Header(
            flags: flags,
            width: width,
            height: height,
            pitchOrLinearSize: pitchOrLinearSize,
            mipCount: mipCount,
            pixelFormat: pixelFormat
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

        // Supported layouts are 32-bit, so scan lines need no padding.
        // Validate the declared top-level pitch, then derive every mip stride.
        // Microsoft DDS_HEADER:
        // https://learn.microsoft.com/en-us/windows/win32/direct3ddds/dds-header
        let expectedPitch = UInt32(header.width) * 4
        guard
            header.flags & Layout.flagPitch != 0,
            header.pitchOrLinearSize == expectedPitch
        else {
            throw DDSError.malformed(
                "uncompressed pitch \(header.pitchOrLinearSize) != expected \(expectedPitch)"
            )
        }
        if isXRGB {
            return .xrgb8888
        }
        return isBGRA ? .bgra8888 : .rgba8888
    }

    /// FourCC -> format; "DX10" pulls the format out of DDS_HEADER_DXT10 and
    /// rejects non-2D resources. Returns whether the file declared sRGB.
    private static func resolveFormat(
        fourCC: FourCC,
        reader: inout BinaryReader
    ) throws -> (DDSPixelFormat, sRGB: Bool) {
        guard fourCC == "DX10" else {
            return try (resolveLegacyFormat(fourCC), false)
        }

        // DDS_HEADER_DXT10 (20 bytes). sRGB DXGI codes are UNORM + 1.
        let dxgiFormat = try reader.readUInt32()
        let dimension = try reader.readUInt32()
        let miscFlag = try reader.readUInt32()
        let arraySize = try reader.readUInt32()
        reader.skip(4) // miscFlags2 (alpha mode)

        guard dimension == Layout.dimensionTexture2D else {
            throw DDSError.unsupported("resource dimension \(dimension)")
        }
        if miscFlag & Layout.miscTextureCube != 0 {
            throw DDSError.unsupported("cubemap")
        }
        guard arraySize <= 1 else {
            throw DDSError.unsupported("texture array of \(arraySize)")
        }
        return try resolveDXGIFormat(dxgiFormat)
    }

    private static func resolveLegacyFormat(_ fourCC: FourCC) throws -> DDSPixelFormat {
        switch fourCC {
        case "DXT1": return .bc1
        case "DXT3": return .bc2
        case "DXT5": return .bc3
        case "ATI1", "BC4U": return .bc4
        case "ATI2", "BC5U": return .bc5
        default:
            throw DDSError.unsupported("FourCC \(fourCC)")
        }
    }

    private static func resolveDXGIFormat(
        _ dxgiFormat: UInt32
    ) throws -> (DDSPixelFormat, sRGB: Bool) {
        switch dxgiFormat {
        case DDSPixelFormat.bc1.rawValue: return (.bc1, false)
        case DDSPixelFormat.bc2.rawValue: return (.bc2, false)
        case DDSPixelFormat.bc3.rawValue: return (.bc3, false)
        case DDSPixelFormat.bc4.rawValue: return (.bc4, false)
        case DDSPixelFormat.bc5.rawValue: return (.bc5, false)
        case DDSPixelFormat.bc7.rawValue: return (.bc7, false)
        // BC1/2/3/7 _SRGB codes are UNORM + 1; 81/84 are BC4/BC5 _SNORM.
        case DDSPixelFormat.bc1.rawValue + 1: return (.bc1, true)
        case DDSPixelFormat.bc2.rawValue + 1: return (.bc2, true)
        case DDSPixelFormat.bc3.rawValue + 1: return (.bc3, true)
        case DDSPixelFormat.bc7.rawValue + 1: return (.bc7, true)
        default: throw DDSError.unsupported("DXGI format \(dxgiFormat)")
        }
    }

    /// Tightly packed chain inside `bytes` (payload start ..< file end): each
    /// level is ceil(w/4) * ceil(h/4) blocks (DDS guide block-size math).
    private static func mipRanges(
        width: Int,
        height: Int,
        mipCount: Int,
        format: DDSPixelFormat,
        bytes: Range<Int>
    ) throws -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var offset = bytes.lowerBound
        for level in 0 ..< mipCount {
            let blockDimension = format.blockDimension
            let blocksWide = (max(1, width >> level) + blockDimension - 1) / blockDimension
            let blocksHigh = (max(1, height >> level) + blockDimension - 1) / blockDimension
            let size = blocksWide * blocksHigh * format.bytesPerBlock
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
    func width(level: Int) -> Int {
        max(1, width >> level)
    }

    func height(level: Int) -> Int {
        max(1, height >> level)
    }

    /// Payload bytes of one mip level.
    func mipData(level: Int) -> Data {
        data.subdata(
            in: (data.startIndex + mipRanges[level].lowerBound)
                ..< (data.startIndex + mipRanges[level].upperBound)
        )
    }

    /// Bytes per row — `MTLTexture.replace` stride.
    func bytesPerRow(level: Int) -> Int {
        let blockDimension = format.blockDimension
        return (width(level: level) + blockDimension - 1) / blockDimension
            * format.bytesPerBlock
    }
}
