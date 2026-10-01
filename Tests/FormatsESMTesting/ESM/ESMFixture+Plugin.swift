import FormatsCoreTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import Testing

extension ESMFixture {
    /// A parsed plugin with one top group per record type, in type order.
    public static func plugin(masters: [String] = [], records: [Data]) throws -> ESMFile {
        let grouped = Dictionary(grouping: records) { record in
            String(bytes: record.prefix(4), encoding: .ascii) ?? ""
        }
        var data = tes4(masters: masters)
        for (type, groupedRecords) in grouped.sorted(by: { $0.key < $1.key }) {
            data += topGroup(type, contents: groupedRecords.reduce(Data(), +))
        }
        return try ESMFile(data: data)
    }

    /// The first record of the `type` top group in `file`.
    public static func firstRecord(type: String, in file: ESMFile) throws -> ESMRecord {
        let group = try #require(file.topGroups.first { $0.recordType?.description == type })
        let child = try #require(try group.children().first)
        guard case let .record(record) = child else {
            throw ESMError.malformed("fixture child is not a record")
        }
        return record
    }

    /// The one record a single-record plugin of `type` parses back to.
    public static func parsedRecord(
        type: String,
        fields: Data,
        formID: UInt32 = 1
    ) throws -> ESMRecord {
        let file = try ESMFile(
            data: tes4() + topGroup(type, contents: record(type, formID: formID, data: fields))
        )
        return try firstRecord(type: type, in: file)
    }

    /// The record that standalone record bytes parse to.
    public static func parseRecord(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    /// Little-endian `uint32` values, back to back.
    public static func words(_ values: [UInt32]) -> Data {
        var data = Data()
        for value in values {
            data.appendUInt32(value)
        }
        return data
    }
}
