// The records the race menu offers choices from: the playable head parts, the form
// lists that name their races, and the colours. See docs/engine/race-menu.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct ChargenRecords: Sendable {
    /// HDPT records with the playable flag, in load order.
    public let headParts: [HeadPart]
    public let formLists: [UInt32: FormList]
    public let colors: [UInt32: ColorForm]

    public init(headParts: [HeadPart], formLists: [UInt32: FormList], colors: [UInt32: ColorForm]) {
        self.headParts = headParts
        self.formLists = formLists
        self.colors = colors
    }

    /// Every plugin's records; a later plugin's override wins.
    public init(loadOrder: LoadOrderPlugins, skipped: inout SkippedRecords) {
        let parts = loadOrder.indexRecords(of: "HDPT", skipped: &skipped) {
            try HeadPart(record: $0, localized: $1)
        }
        headParts = parts.keys.sorted().compactMap { parts[$0] }
            .filter { $0.flags.contains(.playable) }
        formLists = loadOrder.indexRecords(of: "FLST", skipped: &skipped) {
            try FormList(record: $0)
        }
        colors = loadOrder.indexRecords(of: "CLFM", skipped: &skipped) {
            try ColorForm(record: $0, localized: $1)
        }
    }

    /// The playable parts of `type` a race and sex may wear. A part without a
    /// race list fits every race.
    public func parts(_ type: HeadPart.PartType, race: FormID, isFemale: Bool) -> [HeadPart] {
        headParts.filter { part in
            guard part.partType == type else { return false }
            let sexFlag: HeadPart.Flags = isFemale ? .female : .male
            guard part.flags.contains(sexFlag) else { return false }
            guard let list = part.validRaces else { return true }
            return formLists[list.rawValue]?.entries.contains(race) ?? false
        }
    }
}
