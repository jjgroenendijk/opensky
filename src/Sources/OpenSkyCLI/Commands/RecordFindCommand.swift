// `record find --type <type> --where <filter>`: every winning record of one type whose
// decoded fields match the filters. The matching lives in `RecordFieldFilter`.

import Foundation
import OpenSkyCLIArguments
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPreview

enum RecordFindCommand {
    static func run(context: CLIContext, arguments: RecordArguments.Find) throws {
        guard let type = FourCC(text: arguments.type.uppercased()) else {
            throw CLIError.usage("--type expects a four-letter record type")
        }
        let filters = try arguments.filters.map { text in
            guard let filter = RecordFieldFilter(text) else {
                throw CLIError.usage("cannot read --where \(text); see 'record find --help'")
            }
            return filter
        }
        let loadOrder = try context.loadOrder()
        let index = RecordIndex(
            plugins: loadOrder.files,
            recordTypes: RecordDecoders.decodedTypes.subtracting(RecordCommand.unindexedTypes)
                .union([type])
        )
        let ids = index.orderedRecordIDs(of: [type])
        var matched = 0
        for id in ids {
            guard case let .record(indexed) = index.lookup(id) else { continue }
            let fields = fields(of: indexed, id: id, index: index)
            guard filters.allSatisfy({ $0.matches(fields) }) else { continue }
            matched += 1
            if !arguments.count {
                print(line(fields, arguments: arguments))
            }
            if let limit = arguments.limit, matched >= limit {
                break
            }
        }
        if arguments.count {
            print(matched)
        }
        printError("[INFO] \(matched) of \(ids.count) \(type) records matched")
    }

    /// The pseudo fields every type has, then the decoded fields.
    private static func fields(
        of indexed: IndexedRecord, id: ResolvedFormID, index: RecordIndex
    ) -> [RecordField] {
        var fields = [
            RecordField(path: "formID", value: id.description),
            RecordField(path: "plugin", value: indexed.sourcePlugin)
        ]
        fields += ((try? indexed.record.fields()) ?? []).map {
            RecordField(path: "subrecords", value: $0.type.description)
        }
        guard RecordDecoders.decoder(for: indexed.record.type) != nil else { return fields }
        do {
            let value = try RecordDecoders.decode(indexed.record, localized: indexed.localized)
            fields += RecordFields.flatten(value) { raw in
                editorID(raw, fromPlugin: indexed.sourcePlugin, index: index)
            }
        } catch {
            printError("[WARNING] \(id) \(indexed.record.type) decode failed: \(error)")
        }
        return fields
    }

    private static func editorID(
        _ raw: FormID,
        fromPlugin plugin: String,
        index: RecordIndex
    ) -> String {
        switch index.resolve(raw, fromPlugin: plugin) {
        case .nullReference: return "NULL"
        case let .unavailablePlugin(name): return "[UNRESOLVED source \(name)] \(raw)"
        case let .resolved(id):
            guard case let .record(target) = index.lookup(id) else { return id.description }
            return ReferenceRecordCatalog.editorID(in: target.record) ?? id.description
        }
    }

    private static func line(_ fields: [RecordField], arguments: RecordArguments.Find) -> String {
        if arguments.json {
            return json(fields)
        }
        let formID = RecordFieldFilter.values(at: "formID", in: fields).first ?? ""
        let paths = arguments.fields?.items ?? ["editorID"]
        let columns = paths.map { path in
            let values = RecordFieldFilter.values(at: path, in: fields)
            return "\(path)=\(values.isEmpty ? "-" : values.joined(separator: ","))"
        }
        return ([formID] + columns).joined(separator: "\t")
    }

    /// One object per record; a path that repeats becomes a list.
    private static func json(_ fields: [RecordField]) -> String {
        var object: [String: Any] = [:]
        for field in fields {
            switch object[field.path] {
            case nil: object[field.path] = field.value
            case let list as [String]: object[field.path] = list + [field.value]
            case let single as String: object[field.path] = [single, field.value]
            default: break
            }
        }
        guard
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}
