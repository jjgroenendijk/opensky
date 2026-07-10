// Synthetic NIF byte builder shared by NIF parser tests. Fixtures are built
// in code — never extracted game files (AGENTS.md "Legal & IP boundary").
// Layouts follow NifTools nif.xml (Header, BSStreamHeader, Footer); see
// docs/formats/nif.md.

import Foundation

enum NIFFixture {
    static let versionLine = "Gamebryo File Format, Version 20.2.0.7"
    static let version: UInt32 = 0x1402_0007

    /// One block as fed to `header(blocks:)`: type name + raw payload bytes.
    struct Block {
        let type: String
        let data: Data
        /// Set to test the PhysX flag bit on the block type index.
        var physXFlag = false

        init(_ type: String, _ data: Data, physXFlag: Bool = false) {
            self.type = type
            self.data = data
            self.physXFlag = physXFlag
        }
    }

    /// uint32 length + bytes, no terminator (nif.xml SizedString).
    static func sizedString(_ string: String) -> Data {
        var out = Data()
        out.appendUInt32(UInt32(string.utf8.count))
        out.append(Data(string.utf8))
        return out
    }

    /// byte length including a trailing null (nif.xml ExportString).
    static func exportString(_ string: String) -> Data {
        var out = Data([UInt8(string.utf8.count + 1)])
        out.append(Data(string.utf8))
        out.append(0)
        return out
    }

    /// Header bytes. Block type table is derived from `blocks` in first-seen
    /// order. `userVersion` >= 3 emits a BSStreamHeader.
    static func header(
        versionLine: String = versionLine,
        version: UInt32 = version,
        endian: UInt8 = 1,
        userVersion: UInt32 = 12,
        bsVersion: UInt32 = 100,
        blocks: [Block] = [],
        strings: [String] = [],
        groups: [UInt32] = []
    ) -> Data {
        var types: [String] = []
        for block in blocks where !types.contains(block.type) {
            types.append(block.type)
        }

        var out = Data(versionLine.utf8)
        out.append(0x0A)
        out.appendUInt32(version)
        out.append(endian)
        out.appendUInt32(userVersion)
        out.appendUInt32(UInt32(blocks.count))
        if userVersion >= 3 {
            out.appendUInt32(bsVersion)
            out.append(exportString("OpenSky Tests"))
            out.append(exportString(""))
            out.append(exportString(""))
        }
        out.appendUInt16(UInt16(types.count))
        for type in types {
            out.append(sizedString(type))
        }
        for block in blocks {
            let index = UInt16(types.firstIndex(of: block.type) ?? 0)
            out.appendUInt16(block.physXFlag ? index | 0x8000 : index)
        }
        for block in blocks {
            out.appendUInt32(UInt32(block.data.count))
        }
        out.appendUInt32(UInt32(strings.count))
        out.appendUInt32(UInt32(strings.map(\.utf8.count).max() ?? 0))
        for string in strings {
            out.append(sizedString(string))
        }
        out.appendUInt32(UInt32(groups.count))
        for group in groups {
            out.appendUInt32(group)
        }
        return out
    }

    /// Full file: header, block payloads back to back, footer roots.
    static func file(
        blocks: [Block],
        strings: [String] = [],
        groups: [UInt32] = [],
        roots: [Int32] = [0]
    ) -> Data {
        var out = header(blocks: blocks, strings: strings, groups: groups)
        for block in blocks {
            out.append(block.data)
        }
        out.appendUInt32(UInt32(roots.count))
        for root in roots {
            out.appendUInt32(UInt32(bitPattern: root))
        }
        return out
    }
}
