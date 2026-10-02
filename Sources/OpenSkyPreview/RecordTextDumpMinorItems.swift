// Satellite of RecordTextDump: decoded-summary lines for KEYM, SLGM, and APPA.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated extension RecordTextDump {
    static func minorItemSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: KeywordContext?
    ) throws -> String? {
        switch record.type {
        case "KEYM":
            let key = try KeyItem(record: record, localized: localized)
            return "decoded KEYM: " + sharedItemText(key.fields, key.itemValue, context)
                + ", playable \(key.isPlayable)" + skippedText(key.skipped)
        case "SLGM":
            let gem = try SoulGem(record: record, localized: localized)
            return "decoded SLGM: " + sharedItemText(gem.fields, gem.itemValue, context)
                + ", soul \(soulText(gem.containedSoul)), capacity \(soulText(gem.capacity))"
                + ", linked \(gem.linkedGem?.description ?? "-")"
                + ", NPC soul \(gem.canHoldNPCSoul)" + skippedText(gem.skipped)
        case "APPA":
            let apparatus = try Apparatus(record: record, localized: localized)
            let quality = apparatus.quality.map { "\($0)" } ?? "-"
            return "decoded APPA: "
                + sharedItemText(apparatus.fields, apparatus.itemValue, context)
                + ", quality \(quality)" + skippedText(apparatus.skipped)
        default:
            return nil
        }
    }

    private static func soulText(_ level: SoulLevel?) -> String {
        level.map { "\($0)" } ?? "-"
    }

    static func skippedText(_ tally: FieldTally) -> String {
        guard !tally.isEmpty else { return "" }
        let names = tally.ranked.map { "\($0.name) x\($0.count)" }
        return ", unread [\(names.joined(separator: ", "))]"
    }
}
