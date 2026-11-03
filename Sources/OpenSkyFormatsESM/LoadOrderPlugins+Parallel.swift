// The load-order decode on every core. Each worker decodes a run of one plugin's
// records inside that plugin's FormID scope. The merge then runs in load order on
// the calling thread, so the result is the serial one, whatever thread finished first.

import Foundation
import OpenSkyFormatsCore

nonisolated extension LoadOrderPlugins {
    /// Records per work item: enough to pay for the hand-off, small enough to balance.
    static let parallelBatchSize = 64

    /// Decoded `type` records keyed by load-order FormID, decoded on every core.
    public func indexRecordsInParallel<Value: Sendable>(
        of type: FourCC,
        skipped: inout SkippedRecords,
        using decode: @Sendable (ESMRecord, Bool) throws -> Value?
    ) -> [UInt32: Value] {
        let decoded = decodedRecordsInParallel(of: type, skipped: &skipped) { record, plugin in
            try decode(record, plugin.localized)
        }
        return Dictionary(uniqueKeysWithValues: decoded.values.map { ($0.key.rawValue, $0.value) })
    }

    /// The same, for a decoder that needs no localized flag.
    public func indexRecordsInParallel<Value: Sendable>(
        of type: FourCC,
        skipped: inout SkippedRecords,
        using decode: @Sendable (ESMRecord) throws -> Value?
    ) -> [UInt32: Value] {
        indexRecordsInParallel(of: type, skipped: &skipped) { record, _ in try decode(record) }
    }

    private struct Batch: Sendable {
        let plugin: Int
        let range: Range<Int>
    }

    private func decodedRecordsInParallel<Value: Sendable>(
        of type: FourCC,
        skipped: inout SkippedRecords,
        using decode: @Sendable (ESMRecord, LoadOrderPlugin) throws -> Value?
    ) -> (order: [FormID], values: [FormID: Value]) {
        guard LoadOptimisations.isOn(.parallelRecords) else {
            return decodedRecords(of: type, skipped: &skipped, using: decode)
        }
        let records = liveRecordsByPlugin(of: type, skipped: &skipped)
        let batches = records.indices.flatMap { plugin in
            stride(from: 0, to: records[plugin].count, by: Self.parallelBatchSize).map { start in
                Batch(
                    plugin: plugin,
                    range: start ..< min(start + Self.parallelBatchSize, records[plugin].count)
                )
            }
        }
        let plugins = plugins
        let decoded = ParallelDecode.map(batches.indices) { index in
            let batch = batches[index]
            let plugin = plugins[batch.plugin]
            return plugin.decode {
                records[batch.plugin][batch.range].map { record in
                    Result { try decode(record, plugin) }
                }
            }
        }
        var results = records.map { _ in [Result<Value?, any Error>]() }
        for index in batches.indices {
            results[batches[index].plugin] += decoded[index] ?? []
        }
        return merged(records: records, results: results, type: type, skipped: &skipped)
    }
}
