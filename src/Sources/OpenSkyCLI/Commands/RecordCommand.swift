// `record show <id>`: locate the winning record in the load order and write the
// shared RecordTextDump to a file, without the preview pane's caps. A FormID token
// is 1-8 hex digits (0x optional) in the load-order space; anything else is an
// editor ID, found by an EDID scan of every plugin.

import Foundation
import OpenSkyCLIArguments
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPreview

enum RecordCommand {
    static func show(context: CLIContext, arguments: RecordArguments.Show) throws {
        let token = arguments.id
        let loadOrder = try context.loadOrder()
        let found = try find(token: token, in: loadOrder.plugins)
        let index = RecordIndex(
            plugins: loadOrder.files,
            recordTypes: RecordIndex.referenceRecordTypes
                .union(ReferenceRecordCatalog.inspectedItemTypes)
                .union(RecordDecoders.decodedTypes.subtracting(Self.unindexedTypes))
        )
        let inspector = ReferenceRecordInspector(index: index)
        let preview = PreviewRecord(
            record: found.record,
            sourcePlugin: found.plugin.name,
            localized: found.localized,
            resolvedID: loadOrder.plugins.space.resolve(found.formID)
        )
        let text = DumpLimits.$current.withValue(.complete) { inspector.text(for: preview) }
        guard !arguments.print else {
            print(text)
            return
        }
        let file = try outputFile(arguments.out, token: token)
        try Data((text + "\n").utf8).write(to: file)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if let header = lines.first {
            print(header)
        }
        print("[INFO] wrote \(lines.count) lines -> \(file.path(percentEncoded: false))")
    }

    private static func outputFile(_ out: String?, token: String) throws -> URL {
        if let out {
            return URL(filePath: out)
        }
        let safe = String(token.map { $0.isLetter || $0.isNumber ? $0 : "_" })
        return try RunDirectory.create("record-show").appending(path: "\(safe).txt")
    }

    /// Placed and geometry records: too many to index for one dump, and rarely a link target.
    static let unindexedTypes: Set<FourCC> = [
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
