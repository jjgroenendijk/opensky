// Decodes records through `RecordDecoders` and counts what did not decode: a type
// with no decoder, a decode that threw, and the fields each decoder's skip tally
// left unread. The real-data coverage test and `openskycli gaps` share it.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct RecordCoverageSweep: Sendable {
    /// Records seen per type.
    public private(set) var counts: [FourCC: Int] = [:]
    /// Records of a type with no decoder.
    public private(set) var missing: [FourCC: Int] = [:]
    /// Records that threw, per type.
    public private(set) var failureCounts: [FourCC: Int] = [:]
    /// The first failures, verbatim, for a report.
    public private(set) var failures: [String] = []
    /// Type -> skip-tally entry name -> count.
    public private(set) var unread: [FourCC: [String: Int]] = [:]
    /// Decoded types whose value carries no `skipped` tally.
    public private(set) var untallied: Set<FourCC> = []

    public static let failureLimit = 50

    public init() {}

    public var recordTotal: Int {
        counts.values.reduce(0, +)
    }

    /// Unread entries whose name starts with "unknown ", over every type.
    public var unknownFieldTotal: Int {
        unread.values.flatMap(\.self)
            .filter { $0.key.hasPrefix("unknown ") }
            .reduce(0) { $0 + $1.value }
    }

    /// Every live record of `file`, the TES4 header included.
    public mutating func sweep(_ file: ESMFile) {
        decode(file.tes4, localized: file.isLocalized)
        ESMWalk.forEachRecord(in: file) { record in
            if !record.isDeleted {
                decode(record, localized: file.isLocalized)
            }
            return true
        }
    }

    public mutating func decode(_ record: ESMRecord, localized: Bool) {
        counts[record.type, default: 0] += 1
        guard let decode = RecordDecoders.decoder(for: record.type) else {
            missing[record.type, default: 0] += 1
            return
        }
        do {
            let value = try decode(record, localized)
            guard
                let tally = Mirror(reflecting: value).descendant("skipped")
                as? any RankedSkipReport
            else {
                untallied.insert(record.type)
                return
            }
            for entry in tally.ranked {
                unread[record.type, default: [:]][entry.name, default: 0] += entry.count
            }
        } catch {
            failureCounts[record.type, default: 0] += 1
            if failures.count < Self.failureLimit {
                failures.append("\(record.type) \(FormID(record.formID)): \(error)")
            }
        }
    }
}
