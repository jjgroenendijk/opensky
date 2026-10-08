// The table after the plugin lists that says where each body section starts and how
// many entries it holds. See docs/formats/ess.md#file-location-table.

import Foundation

nonisolated public struct ESSFileLocationTable: Equatable, Sendable {
    public let offsets: ESSSectionOffsets
    public let counts: ESSSectionCounts

    public init(offsets: ESSSectionOffsets, counts: ESSSectionCounts) {
        self.offsets = offsets
        self.counts = counts
    }

    init(_ reader: inout ESSReader) throws(ESSError) {
        var words: [UInt32] = []
        for _ in 0 ..< 10 {
            try words.append(reader.uint32("file location table"))
        }
        try reader.skip(15 * 4, "file location table")
        self.init(
            offsets: ESSSectionOffsets(
                formIDArrayCount: words[0], unknownTable3: words[1], globalData1: words[2],
                globalData2: words[3], changeForms: words[4], globalData3: words[5]
            ),
            counts: ESSSectionCounts(
                globalData1: words[6], globalData2: words[7], globalData3: words[8],
                changeForms: words[9]
            )
        )
    }

    /// Body positions of each section. The first global table follows the location
    /// table directly, which fixes what the offsets count from.
    public func sections(
        tableEnd: Int, bodyLength: Int
    ) throws(ESSError) -> ESSSectionPositions {
        let base = Int(offsets.globalData1) - tableEnd
        let ordered: [(String, UInt32)] = [
            ("global data table 1", offsets.globalData1),
            ("global data table 2", offsets.globalData2),
            ("change forms", offsets.changeForms),
            ("global data table 3", offsets.globalData3),
            ("form id array", offsets.formIDArrayCount),
            ("unknown table 3", offsets.unknownTable3)
        ]
        var previous = tableEnd
        var positions: [Int] = []
        for (name, offset) in ordered {
            let position = Int(offset) - base
            guard position >= previous, position <= bodyLength else {
                throw .sectionOutOfRange(section: name, offset: offset)
            }
            positions.append(position)
            previous = position
        }
        return ESSSectionPositions(
            base: base, globalData1: positions[0], globalData2: positions[1],
            changeForms: positions[2], globalData3: positions[3], formIDArray: positions[4],
            unknownTable3: positions[5]
        )
    }
}

nonisolated public struct ESSSectionOffsets: Equatable, Sendable {
    public let formIDArrayCount: UInt32
    public let unknownTable3: UInt32
    public let globalData1: UInt32
    public let globalData2: UInt32
    public let changeForms: UInt32
    public let globalData3: UInt32

    public init(
        formIDArrayCount: UInt32, unknownTable3: UInt32, globalData1: UInt32,
        globalData2: UInt32, changeForms: UInt32, globalData3: UInt32
    ) {
        self.formIDArrayCount = formIDArrayCount
        self.unknownTable3 = unknownTable3
        self.globalData1 = globalData1
        self.globalData2 = globalData2
        self.changeForms = changeForms
        self.globalData3 = globalData3
    }
}

nonisolated public struct ESSSectionCounts: Equatable, Sendable {
    public let globalData1: UInt32
    public let globalData2: UInt32
    /// The game writes one less than the entries present; UESP calls it a harmless bug.
    public let globalData3: UInt32
    public let changeForms: UInt32

    public init(
        globalData1: UInt32,
        globalData2: UInt32,
        globalData3: UInt32,
        changeForms: UInt32
    ) {
        self.globalData1 = globalData1
        self.globalData2 = globalData2
        self.globalData3 = globalData3
        self.changeForms = changeForms
    }
}

/// Section starts as positions in the decompressed body. `base` is what the table's
/// offsets count from.
nonisolated public struct ESSSectionPositions: Equatable, Sendable {
    public let base: Int
    public let globalData1: Int
    public let globalData2: Int
    public let changeForms: Int
    public let globalData3: Int
    public let formIDArray: Int
    public let unknownTable3: Int
}
