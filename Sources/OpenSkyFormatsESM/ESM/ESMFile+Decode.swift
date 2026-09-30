// Decodes the records of one top group in a single plugin. A record whose
// decode throws is noted in `SkippedRecords` instead of vanishing.

import Foundation
import OpenSkyFormatsCore

nonisolated extension ESMFile {
    /// Live `type` records in file order. Deleted records are left out; a nil decode is dropped.
    public func decodeRecords<Value>(
        of type: FourCC,
        skipped: inout SkippedRecords,
        using decode: (ESMRecord) throws -> Value?
    ) -> [Value] {
        var values: [Value] = []
        forEachLiveRecord(of: type, skipped: &skipped) { record in
            if let value = try decode(record) {
                values.append(value)
            }
        }
        return values
    }

    /// The same walk, keyed by each record's raw FormID.
    public func indexRecords<Value>(
        of type: FourCC,
        skipped: inout SkippedRecords,
        using decode: (ESMRecord) throws -> Value?
    ) -> [UInt32: Value] {
        var values: [UInt32: Value] = [:]
        forEachLiveRecord(of: type, skipped: &skipped) { record in
            if let value = try decode(record) {
                values[record.formID] = value
            }
        }
        return values
    }

    private func forEachLiveRecord(
        of type: FourCC,
        skipped: inout SkippedRecords,
        _ body: (ESMRecord) throws -> Void
    ) {
        guard let group = topGroup(of: type) else { return }
        let children: [ESMGroup.Child]
        do {
            children = try group.children()
        } catch {
            skipped.note(type, error: error)
            return
        }
        for case let .record(record) in children where record.type == type && !record.isDeleted {
            do {
                try body(record)
            } catch {
                skipped.note(type, error: error)
            }
        }
    }
}
