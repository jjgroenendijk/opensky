// M21 relationship summaries — RELA and ASTP — kept out of RecordTextDump's
// capped dispatch switch. The formatter feeds both `openskycli record` and the
// Asset Browser.

import Foundation

nonisolated extension RecordTextDump {
    static func relationshipSummary(_ record: ESMRecord) -> String? {
        switch record.type {
        case "RELA": relationSummary(record)
        case "ASTP": associationTypeSummary(record)
        default: nil
        }
    }

    /// RELA: the identity line, then the pair and the rank it holds, then the
    /// association-type link. The link is printed raw because the dump decodes
    /// one record and has no load order to resolve it against.
    private static func relationSummary(_ record: ESMRecord) -> String? {
        guard let relationship = try? Relationship(record: record) else { return nil }
        var lines = [
            "decoded RELA: editorID \(relationship.editorID ?? "-"), "
                + "skipped \(relationship.skipped.total)"
        ]
        guard let data = relationship.data else {
            lines.append("  no DATA — the record names no pair")
            return lines.joined(separator: "\n")
        }
        let signed = data.rank.signedRank.map { "\($0)" } ?? "-"
        lines.append(
            "  parent \(linkText(data.parent)), child \(linkText(data.child))"
        )
        lines.append(
            "  rank \(data.rank) (raw \(data.rank.rawValue), GetRelationshipRank \(signed)), "
                + "secret \(data.flags.contains(.secret)), "
                + "header secret \(relationship.headerSecret)"
        )
        lines.append("  association type \(linkText(data.associationType))")
        return lines.joined(separator: "\n")
    }

    /// ASTP: the identity line and the four titles, each printed only when the
    /// record authored it.
    private static func associationTypeSummary(_ record: ESMRecord) -> String? {
        guard let type = try? AssociationType(record: record) else { return nil }
        var lines = [
            "decoded ASTP: editorID \(type.editorID ?? "-"), "
                + "family association \(type.isFamilyAssociation), "
                + "flags 0x\(String(format: "%08X", type.flags.rawValue)), "
                + "skipped \(type.skipped.total)"
        ]
        let titles: [(String, String?)] = [
            ("male parent", type.maleParentTitle),
            ("female parent", type.femaleParentTitle),
            ("male child", type.maleChildTitle),
            ("female child", type.femaleChildTitle)
        ]
        let authored = titles.compactMap { name, title in
            title.map { "\(name) \"\($0)\"" }
        }
        if !authored.isEmpty {
            lines.append("  titles: \(authored.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    private static func linkText(_ id: FormID?) -> String {
        id.map(\.description) ?? "-"
    }
}
