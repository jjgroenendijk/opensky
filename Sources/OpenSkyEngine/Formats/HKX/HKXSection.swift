// Havok packfile section header + fixup tables (todo 6.1). Layout verified
// by probe against SSE files; see HKXHeader.swift for sources and
// docs/formats/hkx-container.md for the byte map.

import Foundation

/// Section header, 48 bytes: 19-byte null-padded ASCII name + 1 separator
/// (0xFF) + 7 u32 offsets. All offsets except `dataStart` are relative to
/// `dataStart`. Observed region order inside a section:
/// [object data | local fixups | global fixups | virtual fixups | end];
/// exports == imports == end on every SSE file probed (no export tables).
nonisolated struct HKXSectionHeader {
    let name: String
    let dataStart: Int
    let localFixupsOffset: Int
    let globalFixupsOffset: Int
    let virtualFixupsOffset: Int
    let exportsOffset: Int
    let importsOffset: Int
    let endOffset: Int

    /// Object data occupies the section start up to the first fixup table.
    var dataSize: Int {
        localFixupsOffset
    }

    var dataEnd: Int {
        dataStart + endOffset
    }

    init(reader: inout BinaryReader) throws {
        let nameFieldOffset = reader.offset
        let nameField = try reader.read(count: 19)
        guard let name = String(bytes: nameField.prefix { $0 != 0 }, encoding: .ascii) else {
            throw BinaryReaderError.invalidString(offset: nameFieldOffset)
        }
        self.name = name
        reader.skip(1) // separator, observed 0xFF
        dataStart = try Int(reader.readUInt32())
        localFixupsOffset = try Int(reader.readUInt32())
        globalFixupsOffset = try Int(reader.readUInt32())
        virtualFixupsOffset = try Int(reader.readUInt32())
        exportsOffset = try Int(reader.readUInt32())
        importsOffset = try Int(reader.readUInt32())
        endOffset = try Int(reader.readUInt32())
    }

    func validate(fileSize: Int) throws {
        let offsets = [
            localFixupsOffset, globalFixupsOffset, virtualFixupsOffset,
            exportsOffset, importsOffset, endOffset
        ]
        guard dataStart >= 0, dataEnd <= fileSize else {
            throw HKXError.sectionOutOfBounds(
                name: name,
                start: dataStart,
                end: dataEnd,
                fileSize: fileSize
            )
        }
        // Regions must be ascending and inside the section payload.
        guard offsets == offsets.sorted(), offsets.allSatisfy({ $0 >= 0 }) else {
            throw HKXError.fixupRangeInvalid(section: name)
        }
    }
}

/// Pointer patch within one section: pointer at `fromOffset` targets
/// `toOffset` (both section-local).
nonisolated struct HKXLocalFixup: Equatable {
    let fromOffset: Int
    let toOffset: Int
}

/// Pointer patch across sections: pointer at `fromOffset` targets
/// `toOffset` inside section `sectionIndex`.
nonisolated struct HKXGlobalFixup: Equatable {
    let fromOffset: Int
    let sectionIndex: Int
    let toOffset: Int
}

/// Object registration: instance at `dataOffset` (section-local) has the
/// class named at `classNameOffset` inside section `classNameSectionIndex`.
/// The packfile's object inventory.
nonisolated struct HKXVirtualFixup: Equatable {
    let dataOffset: Int
    let classNameSectionIndex: Int
    let classNameOffset: Int
}

/// One parsed section: header + decoded fixup tables.
nonisolated struct HKXSection {
    /// Fixup regions are 16-byte aligned; unused tail slots are filled with
    /// 0xFFFFFFFF. A sentinel first word therefore ends the table (observed:
    /// idle files pad the 5-entry virtual table to 64 bytes).
    private static let padSentinel: UInt32 = 0xFFFF_FFFF

    let header: HKXSectionHeader
    let localFixups: [HKXLocalFixup]
    let globalFixups: [HKXGlobalFixup]
    let virtualFixups: [HKXVirtualFixup]

    init(header: HKXSectionHeader, fileData: Data) throws {
        try header.validate(fileSize: fileData.count)
        self.header = header
        localFixups = try Self.readTable(
            fileData,
            header: header,
            from: header.localFixupsOffset,
            to: header.globalFixupsOffset,
            entryWords: 2
        ).map { HKXLocalFixup(fromOffset: Int($0[0]), toOffset: Int($0[1])) }
        globalFixups = try Self.readTable(
            fileData,
            header: header,
            from: header.globalFixupsOffset,
            to: header.virtualFixupsOffset,
            entryWords: 3
        ).map {
            HKXGlobalFixup(
                fromOffset: Int($0[0]),
                sectionIndex: Int($0[1]),
                toOffset: Int($0[2])
            )
        }
        virtualFixups = try Self.readTable(
            fileData,
            header: header,
            from: header.virtualFixupsOffset,
            to: header.exportsOffset,
            entryWords: 3
        ).map {
            HKXVirtualFixup(
                dataOffset: Int($0[0]),
                classNameSectionIndex: Int($0[1]),
                classNameOffset: Int($0[2])
            )
        }
    }

    /// Reads fixed-width u32 tuples until the region ends, a 0xFFFFFFFF pad
    /// sentinel starts an entry, or fewer than `entryWords` words remain
    /// (alignment tail).
    private static func readTable(
        _ fileData: Data,
        header: HKXSectionHeader,
        from: Int,
        to: Int,
        entryWords: Int
    ) throws -> [[UInt32]] {
        var reader = BinaryReader(fileData, offset: header.dataStart + from)
        let end = header.dataStart + to
        var entries: [[UInt32]] = []
        while reader.offset + entryWords * 4 <= end {
            var words: [UInt32] = []
            for _ in 0 ..< entryWords {
                try words.append(reader.readUInt32())
            }
            if words[0] == padSentinel {
                break
            }
            entries.append(words)
        }
        return entries
    }
}
