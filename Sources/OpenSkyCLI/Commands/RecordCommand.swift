// `record <formid-or-editorid>`: locate the winning record in the load order and
// dump it via the shared RecordTextDump (header, decoded engine view, capped field
// list — same text the preview GUI shows). FormID tokens are 1-8 hex digits
// (0x prefix optional) in the load-order space; anything else is treated as an
// editor ID and found by an EDID scan of every plugin.

import Foundation
import OpenSkyCLIArguments
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPreview

enum RecordCommand {
    static func run(context: CLIContext, arguments: RecordArguments) throws {
        let token = arguments.token
        let loadOrder = try context.loadOrder()
        let found = try find(token: token, in: loadOrder.plugins)
        let index = RecordIndex(
            plugins: loadOrder.files,
            recordTypes: RecordIndex.referenceRecordTypes
                .union(ReferenceRecordCatalog.inspectedItemTypes)
                .union(RecordDecoders.decodedTypes.subtracting(Self.unindexedTypes))
        )
        let inspector = ReferenceRecordInspector(index: index)
        print(
            inspector.text(for: PreviewRecord(
                record: found.record,
                sourcePlugin: found.plugin.name,
                localized: found.localized,
                resolvedID: loadOrder.plugins.space.resolve(found.formID)
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

    private static func find(
        token: String,
        in loadOrder: LoadOrderPlugins
    ) throws -> LoadOrderRecord {
        if let formID = FormID(token: token) {
            guard let found = loadOrder.record(withFormID: formID) else {
                throw CLIError.failure("no record with FormID \(formID)")
            }
            return found
        }
        printError("[INFO] scanning EDID fields for \"\(token)\" (slow on the whole load order)")
        guard let found = loadOrder.record(withEditorID: token) else {
            throw CLIError.failure("no record with editor ID \(token)")
        }
        return found
    }
}
