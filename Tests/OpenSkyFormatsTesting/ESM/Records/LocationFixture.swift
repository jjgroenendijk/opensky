// Synthetic LCTN records for the location store and the location conditions.

import Foundation
import OpenSkyFormatsCore

public enum LocationFixture: Sendable {
    /// One `LCEC`, `ACEC`, or `RCEC` field: a worldspace and its grid cells.
    public struct CellList: Sendable {
        public let field: String
        public let worldspace: UInt32
        public let cells: [CellCoordinate]

        public init(_ field: String, worldspace: UInt32, cells: [CellCoordinate]) {
            self.field = field
            self.worldspace = worldspace
            self.cells = cells
        }
    }

    /// An LCTN with an EDID, an optional PNAM parent, optional keywords, and
    /// optional `LCUN` triples of actor base, reference, and location.
    public static func recordBytes(
        _ formID: UInt32,
        _ editorID: String,
        parent: UInt32? = nil,
        keywords: [UInt32] = [],
        uniqueActors: [UInt32] = [],
        cellLists: [CellList] = []
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        if let parent {
            fields += ESMFixture.field("PNAM", ESMFixture.words([parent]))
        }
        if !keywords.isEmpty {
            fields += ESMFixture.field("KSIZ", ESMFixture.words([UInt32(keywords.count)]))
                + ESMFixture.field("KWDA", ESMFixture.words(keywords))
        }
        if !uniqueActors.isEmpty {
            fields += ESMFixture.field("LCUN", ESMFixture.words(uniqueActors))
        }
        for list in cellLists {
            var data = ESMFixture.words([list.worldspace])
            for cell in list.cells {
                data.appendUInt16(UInt16(bitPattern: Int16(cell.y)))
                data.appendUInt16(UInt16(bitPattern: Int16(cell.x)))
            }
            fields += ESMFixture.field(list.field, data)
        }
        return ESMFixture.record("LCTN", formID: formID, data: fields)
    }
}
