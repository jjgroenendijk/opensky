// KYWD/AACT decoded summaries and the optional context that makes item KWDA
// links legible in both the CLI and Asset Browser.

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
        formListContext: FormListContext?
    ) -> String? {
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
