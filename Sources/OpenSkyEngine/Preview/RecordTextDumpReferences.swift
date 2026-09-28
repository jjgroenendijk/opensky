// Reference-record decoded summaries and the optional context that makes item
// and location links legible in both the CLI and Asset Browser.

import Foundation

nonisolated extension RecordTextDump {
    struct KeywordContext {
        let store: KeywordStore
        let sourcePlugin: String
    }

    struct FormListContext {
        let store: FormListStore
        let sourcePlugin: String
    }

    static func referenceRecordSummary(
        record: ESMRecord,
        localized: Bool,
        keywordContext: KeywordContext?,
        formListContext: FormListContext?
    ) -> String? {
        if let dataRecord = dataReferenceSummary(record: record, localized: localized) {
            return dataRecord
        }
        if
            let location = locationRecordSummary(
                record: record,
                localized: localized,
                keywordContext: keywordContext
            )
        {
            return location
        }
        switch record.type {
        case "KYWD":
            guard let keyword = try? Keyword(record: record) else { return nil }
            return summary(
                type: "KYWD",
                editorID: keyword.editorID,
                color: keyword.editorColor,
                skipped: keyword.skipped
            )
        case "AACT":
            guard let action = try? ActionRecord(record: record) else { return nil }
            return summary(
                type: "AACT",
                editorID: action.editorID,
                color: action.editorColor,
                skipped: action.skipped
            )
        case "FLST":
            guard let list = try? FormList(record: record) else { return nil }
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
    ) -> String? {
        switch record.type {
        case "ECZN":
            guard let zone = try? EncounterZone(record: record) else { return nil }
            return "decoded ECZN: editorID \(zone.editorID ?? "-"), "
                + "owner \(zone.owner?.description ?? "-"), "
                + "location \(zone.location?.description ?? "-"), "
                + "levels \(zone.minimumLevel.map(String.init) ?? "-")-"
                + "\(zone.maximumLevel.map(String.init) ?? "-"), "
                + "rank \(zone.rank.map(String.init) ?? "-"), "
                + "flags 0x\(String(zone.flags.rawValue, radix: 16))"
        case "COLL":
            guard let layer = try? CollisionLayer(record: record, localized: localized) else {
                return nil
            }
            return "decoded COLL: editorID \(layer.editorID ?? "-"), "
                + "index \(layer.index.map(String.init) ?? "-"), "
                + "flags 0x\(String(layer.flags.rawValue, radix: 16)), "
                + "\(layer.collidesWith.count) collides-with links"
        case "DOBJ":
            guard let defaults = try? DefaultObjects(record: record) else { return nil }
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
    ) -> String? {
        if record.type == "LCRT" {
            guard let refType = try? LocationRefType(record: record) else { return nil }
            return summary(
                type: "LCRT",
                editorID: refType.editorID,
                color: refType.editorColor,
                skipped: refType.skipped
            )
        }
        guard
            record.type == "LCTN",
            let location = try? Location(record: record, localized: localized)
        else { return nil }
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
