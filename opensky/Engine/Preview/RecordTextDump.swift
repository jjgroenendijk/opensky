// One-record text dump shared by the CLI `record` command and the preview
// GUI detail pane: header line, engine-decoded view (for the record types
// OpenSky decodes), and the raw field list capped for readability. One impl
// so both tools show the same decode (docs/tools/preview-gui.md).

import Foundation

nonisolated enum RecordTextDump {
    /// Big records (Tamriel WRLD carries thousands of RNAMs) get capped so
    /// the dump stays readable; the tail is summarized per field type.
    static let fieldPrintCap = 64

    static func dump(record: ESMRecord, localized: Bool) -> String {
        dump(
            record: record,
            localized: localized,
            keywordContext: nil,
            formListContext: nil
        )
    }

    static func dump(
        record: ESMRecord,
        localized: Bool,
        keywordStore: KeywordStore,
        sourcePlugin: String
    ) -> String {
        dump(
            record: record,
            localized: localized,
            keywordContext: KeywordContext(store: keywordStore, sourcePlugin: sourcePlugin),
            formListContext: nil
        )
    }

    static func dump(
        record: ESMRecord,
        localized: Bool,
        keywordStore: KeywordStore,
        formListStore: FormListStore,
        sourcePlugin: String
    ) -> String {
        dump(
            record: record,
            localized: localized,
            keywordContext: KeywordContext(store: keywordStore, sourcePlugin: sourcePlugin),
            formListContext: FormListContext(store: formListStore, sourcePlugin: sourcePlugin)
        )
    }

    private static func dump(
        record: ESMRecord,
        localized: Bool,
        keywordContext: KeywordContext?,
        formListContext: FormListContext?
    ) -> String {
        var lines = [headerLine(record: record)]
        if
            let decoded = decodedSummary(
                record: record,
                localized: localized,
                keywordContext: keywordContext,
                formListContext: formListContext
            )
        {
            lines.append(decoded)
        }
        lines.append(contentsOf: fieldLines(record: record))
        return lines.joined(separator: "\n")
    }

    private static func headerLine(record: ESMRecord) -> String {
        let flags = String(format: "0x%08X", record.flags.rawValue)
        return "[INFO] \(record.type) \(FormID(record.formID)) — "
            + "\(record.header.dataSize) bytes, flags \(flags), "
            + "form version \(record.header.version)"
    }

    /// Engine-decoded view for the record types OpenSky has decoders for.
    private static func decodedSummary(
        record: ESMRecord,
        localized: Bool,
        keywordContext: KeywordContext?,
        formListContext: FormListContext?
    ) -> String? {
        switch record.type {
        case "WRLD": worldSummary(record: record, localized: localized)
        case "CELL": cellSummary(record: record, localized: localized)
        case "STAT": staticSummary(record: record)
        case "REFR": referenceSummary(record: record)
        case "WTHR": weatherSummary(record: record)
        case "CLMT": climateSummary(record: record)
        case "REGN": regionSummary(record: record)
        case "QUST": questSummary(record: record, localized: localized)
        case "NAVM": navmeshSummary(record: record)
        case "NAVI": navmeshIndexSummary(record: record)
        // Inventory families live in RecordTextDumpItems.swift so this switch
        // stays inside the strict-lint complexity cap.
        default:
            referenceRecordSummary(
                record: record,
                localized: localized,
                keywordContext: keywordContext,
                formListContext: formListContext
            )
                ?? itemSummary(
                    record: record,
                    localized: localized,
                    keywordContext: keywordContext
                )
        }
    }

    private static func worldSummary(record: ESMRecord, localized: Bool) -> String? {
        guard let world = try? Worldspace(record: record, localized: localized) else {
            return nil
        }
        let parent = if let id = world.parent {
            id.description
        } else {
            "-"
        }
        return "decoded WRLD: editorID \(world.editorID ?? "-"), "
            + "parent \(parent), "
            + "flags 0x\(String(world.flags.rawValue, radix: 16))"
    }

    private static func cellSummary(record: ESMRecord, localized: Bool) -> String? {
        guard let cell = try? Cell(record: record, localized: localized) else { return nil }
        let grid = cell.grid.map { "(\($0.x),\($0.y))" } ?? "-"
        return "decoded CELL: editorID \(cell.editorID ?? "-"), grid \(grid), "
            + (cell.isInterior ? "interior" : "exterior")
    }

    private static func staticSummary(record: ESMRecord) -> String? {
        guard let stat = try? StaticObject(record: record) else { return nil }
        return "decoded STAT: editorID \(stat.editorID ?? "-"), "
            + "model \(stat.modelPath ?? "(marker, no MODL)")"
    }

    private static func referenceSummary(record: ESMRecord) -> String? {
        guard let ref = try? PlacedReference(record: record) else { return nil }
        let teleport = ref.teleportDestination.map {
            ", teleport \($0.door) at \(vector($0.placement.position))"
                + " rotation \(vector($0.placement.rotation))"
        } ?? ""
        return "decoded REFR: base \(ref.base), position "
            + "\(vector(ref.placement.position)), rotation "
            + "\(vector(ref.placement.rotation)), scale \(ref.scale)"
            + teleport
    }

    private static func vector(_ value: SIMD3<Float>) -> String {
        "(\(value.x), \(value.y), \(value.z))"
    }

    private static func weatherSummary(record: ESMRecord) -> String? {
        guard let weather = try? Weather(record: record) else { return nil }
        let layers = weather.colors.map { "\($0.count)" } ?? "-"
        let wind = weather.data.map {
            String(format: "%.2f @ %.0f deg", $0.windSpeed, $0.windDirection)
        } ?? "-"
        let precipitation = weather.data.map { "\($0.precipitation)" } ?? "-"
        let fog = weather.fog.map {
            String(format: "day %.0f-%.0f", $0.dayNear, $0.dayFar)
        } ?? "-"
        return "decoded WTHR: editorID \(weather.editorID ?? "-"), "
            + "color layers \(layers), fog \(fog), wind \(wind), "
            + "class \(precipitation)"
    }

    private static func climateSummary(record: ESMRecord) -> String? {
        guard let climate = try? Climate(record: record) else { return nil }
        let timing = climate.timing.map {
            "sunrise \($0.sunriseBegin)-\($0.sunriseEnd), "
                + "sunset \($0.sunsetBegin)-\($0.sunsetEnd) min"
        } ?? "timing -"
        return "decoded CLMT: editorID \(climate.editorID ?? "-"), "
            + "\(climate.weatherList.count) weathers, \(timing)"
    }

    private static func regionSummary(record: ESMRecord) -> String? {
        guard let region = try? Region(record: record) else { return nil }
        let worldspace = region.worldspace.map(\.description) ?? "-"
        let priority = region.weatherPriority.map { "\($0)" } ?? "-"
        return "decoded REGN: editorID \(region.editorID ?? "-"), "
            + "worldspace \(worldspace), \(region.weatherList.count) weathers, "
            + "weather priority \(priority)"
    }

    private static func questSummary(record: ESMRecord, localized: Bool) -> String? {
        guard let quest = try? Quest(record: record, localized: localized) else { return nil }
        let name = switch quest.name {
        case let .inline(text): "\"\(text)\""
        case let .tableID(id): "string #\(id)"
        case nil: "-"
        }
        let skips = quest.skipped.isEmpty
            ? ""
            : ", skipped " + quest.skipped.ranked.map { "\($0.name):\($0.count)" }
            .joined(separator: " ")
        return "decoded QUST: editorID \(quest.editorID ?? "-"), name \(name), "
            + "\(quest.kind.name), priority \(quest.priority), "
            + "flags 0x\(String(quest.flags.rawValue, radix: 16)), "
            + "\(quest.stages.count) stages, \(quest.objectives.count) objectives, "
            + "\(quest.aliases.count) aliases, \(quest.fragments.count) fragments"
            + skips
    }

    /// The navmesh inspector surface (issue #199): selecting a NAVM in the
    /// Asset Browser, or `openskycli record --type NAVM`, shows the decoded
    /// mesh without anything having to draw it yet (16.3, issue #422).
    private static func navmeshSummary(record: ESMRecord) -> String? {
        guard let navmesh = try? Navmesh(record: record) else { return nil }
        let geometry = navmesh.geometry
        let location = switch geometry.location {
        case let .interior(cell): "interior cell \(cell)"
        case let .exterior(world, x, y): "worldspace \(world) grid (\(x),\(y))"
        }
        return "decoded NAVM: editorID \(navmesh.editorID ?? "-"), \(location), "
            + "version \(geometry.version), \(geometry.vertices.count) vertices, "
            + "\(geometry.triangles.count) triangles, \(geometry.edgeLinks.count) edge links, "
            + "\(geometry.doorLinks.count) door links, "
            + "\(geometry.coverTriangleCount) cover triangles (skipped), "
            + "grid divisor \(geometry.gridDivisor)"
    }

    private static func navmeshIndexSummary(record: ESMRecord) -> String? {
        guard let map = try? NavmeshInfoMap(record: record) else { return nil }
        let islands = map.infos.count { $0.flags.contains(.isIsland) }
        return "decoded NAVI: editorID \(map.editorID ?? "-"), version \(map.version), "
            + "\(map.infos.count) navmeshes (\(islands) islands, "
            + "\(map.malformedInfoCount) malformed), "
            + "\(map.deletedNavmeshes.count) deleted, "
            + "\(map.precomputedPathCount) preferred paths and "
            + "\(map.roadMarkerCount) road markers (skipped)"
    }

    private static func fieldLines(record: ESMRecord) -> [String] {
        guard let fields = try? record.fields() else {
            return ["[WARNING] field payload failed to parse"]
        }
        var lines = ["fields (\(fields.count)):"]
        for field in fields.prefix(fieldPrintCap) {
            var line = "  \(field.type) \(field.data.count) bytes"
            if let text = printableZString(field.data) {
                line += " \"\(text)\""
            }
            lines.append(line)
        }
        guard fields.count > fieldPrintCap else { return lines }
        var restCounts: [String: Int] = [:]
        for field in fields.dropFirst(fieldPrintCap) {
            restCounts[field.type.description, default: 0] += 1
        }
        let rest = restCounts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")
        lines.append("  ... \(fields.count - fieldPrintCap) more: \(rest)")
        return lines
    }

    /// Renders a field as text when it looks like a zstring (printable ASCII
    /// + NUL terminator) — EDID/MODL/MAST and friends become readable.
    private static func printableZString(_ data: Data) -> String? {
        guard data.count > 1, data.last == 0 else { return nil }
        let body = data.dropLast()
        guard body.allSatisfy({ (0x20 ... 0x7E).contains($0) }) else { return nil }
        return String(bytes: body, encoding: .utf8)
    }
}
