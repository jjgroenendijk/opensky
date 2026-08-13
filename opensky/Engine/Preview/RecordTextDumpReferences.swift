// KYWD/AACT/LCTN/LCRT decoded summaries and the optional context that makes
// item and location KWDA links legible in both the CLI and Asset Browser.

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
