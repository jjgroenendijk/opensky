// `record <formid-or-editorid>`: locate one record in Skyrim.esm and dump
// header, decoded engine view (for the types OpenSky decodes) and the raw
// field list. FormID tokens are 1-8 hex digits (0x prefix optional);
// anything else is treated as an editor ID and found by full-file EDID scan.

import Foundation

enum RecordCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let token = try scanner.positional("formid-or-editorid")
        try scanner.finish()
        let file = try context.loadSkyrimESM()
        let record = try find(token: token, in: file)
        let localized = (try? file.pluginHeader().isLocalized) ?? false

        let id = FormID(record.formID)
        let flags = String(format: "0x%08X", record.flags.rawValue)
        print("[INFO] \(record.type) \(id) — \(record.header.dataSize) bytes, "
            + "flags \(flags), form version \(record.header.version)")
        if let decoded = decodedSummary(record: record, localized: localized) {
            print(decoded)
        }
        printFields(record: record)
    }

    private static func find(token: String, in file: ESMFile) throws -> ESMRecord {
        if let formID = parseFormID(token) {
            guard let record = ESMWalk.record(withFormID: formID, in: file) else {
                throw CLIError.failure("no record with FormID \(FormID(formID))")
            }
            return record
        }
        printError("[INFO] scanning EDID fields for \"\(token)\" (slow on Skyrim.esm)")
        guard let record = ESMWalk.record(withEditorID: token, in: file) else {
            throw CLIError.failure("no record with editor ID \(token)")
        }
        return record
    }

    private static func parseFormID(_ token: String) -> UInt32? {
        var hex = token.lowercased()
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        guard (1 ... 8).contains(hex.count) else { return nil }
        return UInt32(hex, radix: 16)
    }

    /// Engine-decoded view for the record types OpenSky has decoders for.
    private static func decodedSummary(record: ESMRecord, localized: Bool) -> String? {
        switch record.type {
        case "WRLD":
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
        case "CELL":
            guard let cell = try? Cell(record: record, localized: localized) else { return nil }
            let grid = cell.grid.map { "(\($0.x),\($0.y))" } ?? "-"
            return "decoded CELL: editorID \(cell.editorID ?? "-"), grid \(grid), "
                + (cell.isInterior ? "interior" : "exterior")
        case "STAT":
            guard let stat = try? StaticObject(record: record) else { return nil }
            return "decoded STAT: editorID \(stat.editorID ?? "-"), "
                + "model \(stat.modelPath ?? "(marker, no MODL)")"
        case "REFR":
            guard let ref = try? PlacedReference(record: record) else { return nil }
            let position = ref.placement.position
            return "decoded REFR: base \(ref.base), position "
                + "(\(position.x), \(position.y), \(position.z)), scale \(ref.scale)"
        default:
            return nil
        }
    }

    /// Big records (Tamriel WRLD carries thousands of RNAMs) get capped so
    /// the dump stays readable; the tail is summarized per field type.
    private static let fieldPrintCap = 64

    private static func printFields(record: ESMRecord) {
        guard let fields = try? record.fields() else {
            printError("[WARNING] field payload failed to parse")
            return
        }
        print("fields (\(fields.count)):")
        for field in fields.prefix(fieldPrintCap) {
            var line = "  \(field.type) \(field.data.count) bytes"
            if let text = printableZString(field.data) {
                line += " \"\(text)\""
            }
            print(line)
        }
        guard fields.count > fieldPrintCap else { return }
        var restCounts: [String: Int] = [:]
        for field in fields.dropFirst(fieldPrintCap) {
            restCounts[field.type.description, default: 0] += 1
        }
        let rest = restCounts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")
        print("  ... \(fields.count - fieldPrintCap) more: \(rest)")
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
