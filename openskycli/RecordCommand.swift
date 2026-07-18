// `record <formid-or-editorid>`: locate one record in Skyrim.esm and dump it
// via the shared RecordTextDump (header, decoded engine view, capped field
// list — same text the preview GUI shows). FormID tokens are 1-8 hex digits
// (0x prefix optional); anything else is treated as an editor ID and found
// by full-file EDID scan.

import Foundation

enum RecordCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let token = try scanner.positional("formid-or-editorid")
        try scanner.finish()
        let file = try context.loadSkyrimESM()
        let record = try find(token: token, in: file)
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        print(RecordTextDump.dump(record: record, localized: localized))
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
}
