// Record iteration helpers over a parsed plugin: depth-first walk of every
// group (record headers only — payloads decode only when a caller asks) plus
// lookups by FormID / editor ID and a FormID -> record-type index. Malformed
// subtrees are pruned with a log, never fatal (AGENTS.md mod-quirk rule).
// Shared by the CLI (record/cell commands) and the preview GUI catalog.

import Foundation
import OSLog

nonisolated enum ESMWalk {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "ESMWalk"
    )

    /// Depth-first over every record in every top group (TES4 excluded).
    /// Return false from `body` to stop early.
    static func forEachRecord(in file: ESMFile, _ body: (ESMRecord) -> Bool) {
        for group in file.topGroups {
            guard walk(group: group, body) else { return }
        }
    }

    private static func walk(group: ESMGroup, _ body: (ESMRecord) -> Bool) -> Bool {
        guard let children = try? group.children() else {
            logger.warning("malformed group skipped")
            return true
        }
        for child in children {
            switch child {
            case let .record(record):
                guard body(record) else { return false }
            case let .group(sub):
                guard walk(group: sub, body) else { return false }
            }
        }
        return true
    }

    /// FormID -> record type over the whole plugin (headers only, fast).
    static func recordTypeIndex(in file: ESMFile) -> [UInt32: FourCC] {
        var index: [UInt32: FourCC] = [:]
        forEachRecord(in: file) { record in
            index[record.formID] = record.type
            return true
        }
        return index
    }

    /// First record whose FormID matches (0 is the null sentinel -> nil).
    static func record(withFormID formID: UInt32, in file: ESMFile) -> ESMRecord? {
        guard formID != 0 else { return nil }
        var found: ESMRecord?
        forEachRecord(in: file) { record in
            if record.formID == formID {
                found = record
                return false
            }
            return true
        }
        return found
    }

    /// First record whose EDID matches, case-insensitively. Decodes the
    /// fields of every record until the hit — slow on Skyrim.esm (whole-file
    /// decompression), acceptable for a dev tool.
    static func record(withEditorID editorID: String, in file: ESMFile) -> ESMRecord? {
        let wanted = editorID.lowercased()
        var found: ESMRecord?
        forEachRecord(in: file) { record in
            if let id = Self.editorID(of: record), id.lowercased() == wanted {
                found = record
                return false
            }
            return true
        }
        return found
    }

    /// EDID zstring of a record, nil when absent or undecodable.
    static func editorID(of record: ESMRecord) -> String? {
        guard let fields = try? record.fields() else { return nil }
        for field in fields where field.type == "EDID" {
            var reader = BinaryReader(field.data)
            return try? reader.readZString()
        }
        return nil
    }
}
