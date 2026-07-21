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
        var lines = [headerLine(record: record)]
        if let decoded = decodedSummary(record: record, localized: localized) {
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
    private static func decodedSummary(record: ESMRecord, localized: Bool) -> String? {
        switch record.type {
        case "WRLD": worldSummary(record: record, localized: localized)
        case "CELL": cellSummary(record: record, localized: localized)
        case "STAT": staticSummary(record: record)
        case "REFR": referenceSummary(record: record)
        case "WTHR": weatherSummary(record: record)
        case "CLMT": climateSummary(record: record)
        case "REGN": regionSummary(record: record)
        default: nil
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
        let position = ref.placement.position
        let rotation = ref.placement.rotation
        let teleport = ref.teleportDestination.map {
            ", teleport \($0.door) at \($0.placement.position)"
                + " rotation \($0.placement.rotation)"
        } ?? ""
        return "decoded REFR: base \(ref.base), position "
            + "(\(position.x), \(position.y), \(position.z)), rotation "
            + "(\(rotation.x), \(rotation.y), \(rotation.z)), scale \(ref.scale)"
            + teleport
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
