// M20 progression summaries — AVIF for now — kept out of RecordTextDump's
// capped dispatch switch. The formatter feeds both `openskycli record` and the
// Asset Browser.

import Foundation

nonisolated extension RecordTextDump {
    static func progressionSummary(record: ESMRecord, localized: Bool) -> String? {
        switch record.type {
        case "AVIF": actorValueInformationSummary(record, localized)
        default: nil
        }
    }

    /// AVIF: the identity line, then the advancement parameters and the perk
    /// grid when the record carries them. Perk links print as raw FormIDs —
    /// naming them needs a PERK decoder, which is issue 20.2.
    private static func actorValueInformationSummary(
        _ record: ESMRecord,
        _ localized: Bool
    ) -> String? {
        guard let value = try? ActorValueInformation(record: record, localized: localized) else {
            return nil
        }
        let actorValue = value.vanillaActorValueIndex.map {
            "\(ActorValueIdentity.description(of: $0)) (index \($0))"
        } ?? "not a vanilla actor value"
        var lines = [
            "decoded AVIF: editorID \(value.editorID ?? "-"), "
                + "name \(nameText(value.name)), "
                + "abbreviation \(value.abbreviation ?? "-"), "
                + "actor value \(actorValue), "
                + "category \(value.skillCategory?.description ?? "-"), "
                + "skipped \(value.skipped.total)"
        ]
        if let use = value.skillUse {
            lines.append(String(
                format: "  skill use: use mult %.4f, use offset %.4f, "
                    + "improve mult %.4f, improve offset %.4f",
                use.useMultiplier,
                use.useOffset,
                use.improveMultiplier,
                use.improveOffset
            ))
        }
        lines.append(contentsOf: perkTreeLines(value.perkTree))
        return lines.joined(separator: "\n")
    }

    private static func nameText(_ value: LString?) -> String {
        switch value {
        case let .inline(text): "\"\(text)\""
        case let .tableID(id): "string #\(id)"
        case nil: "-"
        }
    }

    private static func perkTreeLines(_ nodes: [PerkTreeNode]) -> [String] {
        guard !nodes.isEmpty else { return [] }
        let rows = nodes.map { node in
            String(
                format: "    #%d perk %@, grid (%d,%d) offset (%.3f,%.3f), "
                    + "parent required %@, lines to [%@]",
                Int(node.index),
                node.perk?.description ?? "NULL",
                Int(node.position.column),
                Int(node.position.row),
                node.position.horizontal,
                node.position.vertical,
                node.parentRequired ? "yes" : "no",
                node.connections.map(String.init).joined(separator: ", ")
            )
        }
        return ["  perk tree (\(nodes.count) nodes):"] + rows
    }
}
