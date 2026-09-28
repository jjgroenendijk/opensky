// NiAlphaProperty: transparency mode of a shape — one uint16 of packed
// blend/test bits plus a byte threshold. Foliage and other cutouts need the
// alpha-test bit + threshold; actual translucency uses the blend bit.
//
// Reference: NifTools nif.xml (NiAlphaProperty, AlphaFlags bitfield:
// bit 0 blend enable, bits 1-4 source blend mode, bits 5-8 destination
// blend mode, bit 9 test enable, bits 10-12 test function, bit 13 no
// sorter).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif-materials.md.

import Foundation

nonisolated public struct NIFAlphaProperty: Equatable, Sendable {
    public let name: String?
    /// Raw AlphaFlags; derived accessors below.
    public let flags: UInt16
    /// Alpha-test cutoff, 0-255.
    public let threshold: UInt8

    public var blendEnabled: Bool {
        flags & 0x0001 != 0
    }

    /// nif.xml AlphaFunction: 0 ONE, 1 ZERO, 4 DEST_COLOR, 5 INV_DEST_COLOR,
    /// 6 SRC_ALPHA, 7 INV_SRC_ALPHA…
    public var sourceBlendMode: UInt16 {
        (flags >> 1) & 0xF
    }

    public var destinationBlendMode: UInt16 {
        (flags >> 5) & 0xF
    }

    public var testEnabled: Bool {
        flags & 0x0200 != 0
    }

    /// nif.xml TestFunction: 0 ALWAYS … 4 GREATER (default) … 7 NEVER.
    public var testFunction: UInt16 {
        (flags >> 10) & 0x7
    }

    public var noSorter: Bool {
        flags & 0x2000 != 0
    }

    /// Threshold remapped for shader compare against sampled alpha.
    public var testThreshold: Float {
        Float(threshold) / 255
    }

    public init(data: Data, header: NIFHeader) throws {
        var reader = BinaryReader(data)
        name = try NIFObjectNET(reader: &reader, header: header).name
        flags = try reader.readUInt16()
        threshold = try reader.readUInt8()
    }
}
