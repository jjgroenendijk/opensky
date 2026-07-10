// DDS (DirectDraw Surface) texture container for Skyrim SE textures:
// magic, DDS_HEADER, optional DDS_HEADER_DXT10, then a tightly packed mip
// chain. Only 2D block-compressed surfaces (BC1-BC5, BC7) are read — that is
// what vanilla SSE ships; cubemaps, volumes and arrays throw `unsupported`.
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
    /// array, non-BCn pixel format).
    case unsupported(String)
}

/// Block-compressed formats OpenSky reads. Raw values are the DXGI_FORMAT
/// UNORM codes (dxgiformat.h) so probes can print recognizable numbers.
nonisolated enum DDSPixelFormat: UInt32 {
    case bc1 = 71 // DXGI_FORMAT_BC1_UNORM, FourCC "DXT1"
    case bc2 = 74 // DXGI_FORMAT_BC2_UNORM, FourCC "DXT3"
    case bc3 = 77 // DXGI_FORMAT_BC3_UNORM, FourCC "DXT5"
    case bc4 = 80 // DXGI_FORMAT_BC4_UNORM, FourCC "ATI1"/"BC4U"
    case bc5 = 83 // DXGI_FORMAT_BC5_UNORM, FourCC "ATI2"/"BC5U"
    case bc7 = 98 // DXGI_FORMAT_BC7_UNORM, DX10 header only

    /// Bytes per 4x4 texel block (DDS guide "compressed formats").
    var bytesPerBlock: Int {
        switch self {
        case .bc1, .bc4: 8
        case .bc2, .bc3, .bc5, .bc7: 16
        }
    }
}

/// Parsed 2D BCn texture: dimensions, format, and a byte range per mip level.
nonisolated struct DDSFile {
    private enum Layout {
        static let magic: FourCC = "DDS "
        static let headerSize: UInt32 = 124
        static let pixelFormatSize: UInt32 = 32
        /// DDS_HEADER.dwFlags
        static let flagMipMapCount: UInt32 = 0x20000 // DDSD_MIPMAPCOUNT
        /// DDS_PIXELFORMAT.dwFlags
        static let flagFourCC: UInt32 = 0x4 // DDPF_FOURCC
        // DDS_HEADER.dwCaps2
        static let capsCubemap: UInt32 = 0x200 // DDSCAPS2_CUBEMAP
        static let capsVolume: UInt32 = 0x200000 // DDSCAPS2_VOLUME
        // DDS_HEADER_DXT10
        static let dimensionTexture2D: UInt32 = 3 // D3D10_RESOURCE_DIMENSION
        static let miscTextureCube: UInt32 = 0x4 // D3D10_RESOURCE_MISC
        /// Sanity bound; largest vanilla SSE textures are 4096.
        static let maxDimension = 16384
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

        guard try reader.readFourCC() == Layout.magic else {
            throw DDSError.malformed("bad magic (expected \"DDS \")")
        }
        guard try reader.readUInt32() == Layout.headerSize else {
            throw DDSError.malformed("DDS_HEADER.dwSize != 124")
        }
        let flags = try reader.readUInt32()
        height = try Int(reader.readUInt32())
        width = try Int(reader.readUInt32())
        reader.skip(4) // dwPitchOrLinearSize — unreliable in the wild, derived instead
        reader.skip(4) // dwDepth — volumes rejected below via caps2
        let headerMipCount = try Int(reader.readUInt32())
        reader.skip(11 * 4) // dwReserved1

        guard
            (1 ... Layout.maxDimension).contains(width),
            (1 ... Layout.maxDimension).contains(height)
        else {
            throw DDSError.malformed("dimensions \(width)x\(height) out of range")
        }

        // DDS_PIXELFORMAT
        guard try reader.readUInt32() == Layout.pixelFormatSize else {
            throw DDSError.malformed("DDS_PIXELFORMAT.dwSize != 32")
        }
        let pixelFlags = try reader.readUInt32()
        let fourCC = try reader.readFourCC()
        reader.skip(5 * 4) // dwRGBBitCount + 4 channel masks — uncompressed only

        reader.skip(4) // dwCaps
        let caps2 = try reader.readUInt32()
        reader.skip(3 * 4) // dwCaps3, dwCaps4, dwReserved2
        if caps2 & Layout.capsCubemap != 0 {
            throw DDSError.unsupported("cubemap")
        }
        if caps2 & Layout.capsVolume != 0 {
            throw DDSError.unsupported("volume texture")
        }

        guard pixelFlags & Layout.flagFourCC != 0 else {
            throw DDSError.unsupported("uncompressed pixel format (no FourCC)")
        }
        (format, declaresSRGB) = try Self.resolveFormat(fourCC: fourCC, reader: &reader)

        // DDSD_MIPMAPCOUNT absent -> single level, whatever dwMipMapCount says.
        let claimedMips = flags & Layout.flagMipMapCount != 0 ? max(1, headerMipCount) : 1
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

    /// FourCC -> format; "DX10" pulls the format out of DDS_HEADER_DXT10 and
    /// rejects non-2D resources. Returns whether the file declared sRGB.
    private static func resolveFormat(
        fourCC: FourCC,
        reader: inout BinaryReader
    ) throws -> (DDSPixelFormat, sRGB: Bool) {
        switch fourCC {
        case "DXT1": return (.bc1, false)
        case "DXT3": return (.bc2, false)
        case "DXT5": return (.bc3, false)
        case "ATI1", "BC4U": return (.bc4, false)
        case "ATI2", "BC5U": return (.bc5, false)
        case "DX10": break
        default:
            throw DDSError.unsupported("FourCC \(fourCC)")
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

        if let format = DDSPixelFormat(rawValue: dxgiFormat) {
            return (format, false)
        }
        // BC1/2/3/7 _SRGB codes are UNORM + 1; 81/84 are BC4/BC5 _SNORM.
        let srgbBase = dxgiFormat > 0 ? DDSPixelFormat(rawValue: dxgiFormat - 1) : nil
        if let format = srgbBase, format != .bc4, format != .bc5 {
            return (format, true)
        }
        throw DDSError.unsupported("DXGI format \(dxgiFormat)")
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
            let blocksWide = (max(1, width >> level) + 3) / 4
            let blocksHigh = (max(1, height >> level) + 3) / 4
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

    func width(level: Int) -> Int {
        max(1, width >> level)
    }

    func height(level: Int) -> Int {
        max(1, height >> level)
    }

    /// Compressed bytes of one mip level.
    func mipData(level: Int) -> Data {
        data.subdata(
            in: (data.startIndex + mipRanges[level].lowerBound)
                ..< (data.startIndex + mipRanges[level].upperBound)
        )
    }

    /// Bytes per row of 4x4 blocks — `MTLTexture.replace` stride.
    func bytesPerRow(level: Int) -> Int {
        (width(level: level) + 3) / 4 * format.bytesPerBlock
    }
}
