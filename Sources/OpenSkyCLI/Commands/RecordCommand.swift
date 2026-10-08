// `record <formid-or-editorid>`: locate one record in Skyrim.esm and dump it
// via the shared RecordTextDump (header, decoded engine view, capped field
// list — same text the preview GUI shows). FormID tokens are 1-8 hex digits
// (0x prefix optional); anything else is treated as an editor ID and found
// by full-file EDID scan.

import Foundation
import OpenSkyCLIArguments
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPreview

enum RecordCommand {
    static func run(context: CLIContext, arguments: RecordArguments) throws {
        let token = arguments.token
        let file = try context.loadSkyrimESM()
        let record = try find(token: token, in: file)
        let localized = file.isLocalized
        let plugins = ActivePluginFiles.load(root: context.root, baseFile: file)
        let index = RecordIndex(
            plugins: plugins,
            recordTypes: RecordIndex.referenceRecordTypes
                .union(ReferenceRecordCatalog.inspectedItemTypes)
                .union(RecordDecoders.decodedTypes.subtracting(Self.unindexedTypes))
        )
        let inspector = ReferenceRecordInspector(index: index)
        print(
            inspector.text(for: PreviewRecord(
                record: record,
                sourcePlugin: "Skyrim.esm",
                localized: localized,
                resolvedID: nil
            ))
        )
    }

    /// Placed and geometry records: too many to index for one dump, and rarely a link target.
    private static let unindexedTypes: Set<FourCC> = [
        "REFR",
        "ACHR",
        "PGRE",
        "PHZD",
        "NAVM",
        "LAND"
    ]

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
