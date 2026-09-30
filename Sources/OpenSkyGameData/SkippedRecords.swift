// Records a store dropped because their typed decode threw. Malformed input
// must stay visible, so every store counts its skips here instead of `try?`.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct SkippedRecords: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public fileprivate(set) var count: Int
        /// Only the first error is kept, so a mod with many broken records stays cheap.
        public let firstError: String
    }

    public private(set) var byType: [FourCC: Entry] = [:]

    public init() {}

    public var total: Int {
        byType.values.reduce(0) { $0 + $1.count }
    }

    public var isEmpty: Bool {
        byType.isEmpty
    }

    public func count(of type: FourCC) -> Int {
        byType[type]?.count ?? 0
    }

    /// One line per record type, sorted by type, for inspectors and test logs.
    public var lines: [String] {
        byType
            .sorted { $0.key.description < $1.key.description }
            .map { "\($0.key): \($0.value.count) skipped, first error: \($0.value.firstError)" }
    }

    public mutating func note(_ type: FourCC, error: any Error) {
        if byType[type] == nil {
            byType[type] = Entry(count: 1, firstError: String(describing: error))
        } else {
            byType[type]?.count += 1
        }
    }

    /// Adds `other`'s counts. A type already present keeps its own first error.
    public mutating func merge(_ other: Self) {
        for (type, entry) in other.byType {
            if byType[type] == nil {
                byType[type] = entry
            } else {
                byType[type]?.count += entry.count
            }
        }
    }

    public func merging(_ other: Self) -> Self {
        var merged = self
        merged.merge(other)
        return merged
    }

    /// Decodes `record`, or notes the error under the record's type and returns nil.
    public mutating func decode<Value>(
        _ record: ESMRecord,
        using decode: (ESMRecord) throws -> Value
    ) -> Value? {
        do {
            return try decode(record)
        } catch {
            note(record.type, error: error)
            return nil
        }
    }
}
