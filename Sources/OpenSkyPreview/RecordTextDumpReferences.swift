// Reference-record decoded summaries and the optional context that makes item
// and location links legible in both the CLI and Asset Browser.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension RecordTextDump {
    public struct KeywordContext: Sendable {
        public let store: KeywordStore
        public let sourcePlugin: String
    }

    public struct FormListContext: Sendable {
        public let store: FormListStore
        public let sourcePlugin: String
    }

    public static func referenceRecordSummary(
        record: ESMRecord,
        localized: Bool,
        keywordContext: KeywordContext?,
        formListContext: FormListContext?
    ) throws -> String? {
        if let dataRecord = try dataReferenceSummary(record: record, localized: localized) {
            return dataRecord
        }
        if
            let location = try locationRecordSummary(
                record: record,
                localized: localized,
                keywordContext: keywordContext
            )
        {
            return location
        }
        switch record.type {
        case "KYWD":
            let keyword = try Keyword(record: record)
            return summary(
                type: "KYWD",
                editorID: keyword.editorID,
                color: keyword.editorColor,
                skipped: keyword.skipped
            )
        case "AACT":
            let action = try ActionRecord(record: record)
            return summary(
                type: "AACT",
                editorID: action.editorID,
                color: action.editorColor,
                skipped: action.skipped
            )
        case "FLST":
            let list = try FormList(record: record)
            let entries = list.entries.prefix(fieldPrintCap).map { entry in
                if let formListContext {
                    formListContext.store.displayString(
                        for: entry,
                        fromPlugin: formListContext.sourcePlugin
                    )
                } else {
                    entry?.description ?? "NULL"
                }
            }
            var entryText = entries.joined(separator: ", ")
            if list.entries.count > fieldPrintCap {
                entryText += ", ... \(list.entries.count - fieldPrintCap) more"
            }
            return "decoded FLST: editorID \(list.editorID ?? "-"), "
                + "entries \(list.entries.count) [\(entryText)], "
                + "malformed \(list.malformedEntryCount)"
        default:
            return nil
        }
    }

    private static func dataReferenceSummary(
        record: ESMRecord,
        localized: Bool
    ) throws -> String? {
        switch record.type {
        case "ECZN":
            let zone = try EncounterZone(record: record)
            return "decoded ECZN: editorID \(zone.editorID ?? "-"), "
                + "owner \(zone.owner?.description ?? "-"), "
                + "location \(zone.location?.description ?? "-"), "
                + "levels \(zone.minimumLevel.map(String.init) ?? "-")-"
                + "\(zone.maximumLevel.map(String.init) ?? "-"), "
                + "rank \(zone.rank.map(String.init) ?? "-"), "
                + "flags 0x\(String(zone.flags.rawValue, radix: 16))"
        case "COLL":
            let layer = try CollisionLayer(record: record, localized: localized)
            return "decoded COLL: editorID \(layer.editorID ?? "-"), "
                + "index \(layer.index.map(String.init) ?? "-"), "
                + "flags 0x\(String(layer.flags.rawValue, radix: 16)), "
                + "\(layer.collidesWith.count) collides-with links"
        case "DOBJ":
            let defaults = try DefaultObjects(record: record)
            let tags = defaults.entries.prefix(12).map(\.tag.description)
            let suffix = defaults.entries.count > 12 ? ", ..." : ""
            return "decoded DOBJ: editorID \(defaults.editorID), "
                + "\(defaults.entries.count) entries [\(tags.joined(separator: ", "))"
                + "\(suffix)], skipped \(defaults.skipped.total)"
        default:
            return nil
        }
    }

    private static func locationRecordSummary(
        record: ESMRecord,
        localized: Bool,
        keywordContext: KeywordContext?
    ) throws -> String? {
        if record.type == "LCRT" {
            let refType = try LocationRefType(record: record)
            return summary(
                type: "LCRT",
                editorID: refType.editorID,
                color: refType.editorColor,
                skipped: refType.skipped
            )
        }
        guard record.type == "LCTN" else { return nil }
        let location = try Location(record: record, localized: localized)
        let name = switch location.name {
        case let .inline(value): "\"\(value)\""
        case let .tableID(id): "string #\(id)"
        case nil: "-"
        }
        let keywordNames = if let keywordContext {
            location.keywords.displayStrings(
                fromPlugin: keywordContext.sourcePlugin,
                using: keywordContext.store
            )
        } else {
            location.keywords.keywords.map(\.description)
        }
        return "decoded LCTN: editorID \(location.editorID ?? "-"), name \(name), "
            + "parent \(location.parent?.description ?? "-"), "
            + "keywords [\(keywordNames.joined(separator: ", "))]"
    }

    private static func summary(
        type: String,
        editorID: String?,
        color: ReferenceRecordColor?,
        skipped: ReferenceRecordTally
    ) -> String {
        let colorText = color.map {
            "rgba(\($0.red),\($0.green),\($0.blue),\($0.alpha))"
        } ?? "-"
        return "decoded \(type): editorID \(editorID ?? "-"), "
            + "editor color \(colorText), skipped \(skipped.total)"
    }
}
