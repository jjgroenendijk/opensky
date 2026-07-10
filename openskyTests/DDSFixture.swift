// Synthetic DDS byte builder shared by DDS parser tests. Fixtures are built
// in code — never extracted game files (AGENTS.md "Legal & IP boundary").
// Layout follows the Microsoft DDS programming guide (DDS_HEADER,
// DDS_PIXELFORMAT, DDS_HEADER_DXT10); see docs/formats/dds.md.

import Foundation
@testable import opensky

enum DDSFixture {
    /// Optional DDS_HEADER_DXT10 fields (FourCC "DX10").
    struct DX10 {
        var dxgiFormat: UInt32
        var resourceDimension: UInt32 = 3 // D3D10_RESOURCE_DIMENSION_TEXTURE2D
        var miscFlag: UInt32 = 0
        var arraySize: UInt32 = 1
        var miscFlags2: UInt32 = 0
    }

    /// Bytes of one tightly packed BCn mip chain, each byte = its mip level,
    /// so tests can assert slicing by content.
    static func mipChain(width: Int, height: Int, mipCount: Int, blockBytes: Int) -> Data {
        var out = Data()
        for level in 0 ..< mipCount {
            let blocksWide = (max(1, width >> level) + 3) / 4
            let blocksHigh = (max(1, height >> level) + 3) / 4
            out.append(Data(
                repeating: UInt8(truncatingIfNeeded: level),
                count: blocksWide * blocksHigh * blockBytes
            ))
        }
        return out
    }

    /// Full file: magic + DDS_HEADER (+ DXT10 when given) + payload.
    static func file(
        magic: String = "DDS ",
        headerSize: UInt32 = 124,
        flags: UInt32 = 0x1007, // CAPS | HEIGHT | WIDTH | PIXELFORMAT
        width: UInt32,
        height: UInt32,
        mipCount: UInt32 = 0,
        pixelFormatSize: UInt32 = 32,
        pixelFlags: UInt32 = 0x4, // DDPF_FOURCC
        fourCC: String,
        caps2: UInt32 = 0,
        dx10: DX10? = nil,
        payload: Data
    ) -> Data {
        var out = Data(magic.utf8)
        out.appendUInt32(headerSize)
        out.appendUInt32(mipCount > 0 ? flags | 0x20000 : flags) // DDSD_MIPMAPCOUNT
        out.appendUInt32(height)
        out.appendUInt32(width)
        out.appendUInt32(0) // dwPitchOrLinearSize
        out.appendUInt32(0) // dwDepth
        out.appendUInt32(mipCount)
        out.append(Data(count: 11 * 4)) // dwReserved1
        // DDS_PIXELFORMAT
        out.appendUInt32(pixelFormatSize)
        out.appendUInt32(pixelFlags)
        out.append(Data(fourCC.utf8))
        out.append(Data(count: 5 * 4)) // dwRGBBitCount + channel masks
        out.appendUInt32(0x1000) // dwCaps (DDSCAPS_TEXTURE)
        out.appendUInt32(caps2)
        out.append(Data(count: 3 * 4)) // dwCaps3, dwCaps4, dwReserved2
        if let dx10 {
            out.appendUInt32(dx10.dxgiFormat)
            out.appendUInt32(dx10.resourceDimension)
            out.appendUInt32(dx10.miscFlag)
            out.appendUInt32(dx10.arraySize)
            out.appendUInt32(dx10.miscFlags2)
        }
        out.append(payload)
        return out
    }

    /// Well-formed file for `format` with a content-tagged full payload.
    static func file(
        format: DDSPixelFormat,
        width: Int,
        height: Int,
        mipCount: Int,
        dx10: Bool = false,
        srgb: Bool = false
    ) -> Data {
        let fourCC = switch format {
        case .bc1: "DXT1"
        case .bc2: "DXT3"
        case .bc3: "DXT5"
        case .bc4: "ATI1"
        case .bc5: "ATI2"
        case .bc7: "DX10"
        }
        return file(
            width: UInt32(width),
            height: UInt32(height),
            mipCount: UInt32(mipCount),
            fourCC: dx10 || format == .bc7 ? "DX10" : fourCC,
            dx10: dx10 || format == .bc7
                ? DX10(dxgiFormat: format.rawValue + (srgb ? 1 : 0))
                : nil,
            payload: mipChain(
                width: width,
                height: height,
                mipCount: mipCount,
                blockBytes: format.bytesPerBlock
            )
        )
    }
}
