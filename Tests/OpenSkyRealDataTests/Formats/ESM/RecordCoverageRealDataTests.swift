// Whole-install coverage: every live record in the five masters and the
// Creation Club plugins decodes through `RecordDecoders`. A type with no
// decoder, a decode that throws, or a decoder with no skip tally fails the sweep.
// Run with `make test-real T='RecordCoverageRealDataTests'`.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import TagsTesting
import Testing

@Suite(.tags(.smoke))
struct RecordCoverageRealDataTests {
    private struct Sweep {
        var counts: [FourCC: Int] = [:]
        var missing: [FourCC: Int] = [:]
        var failures: [String] = []
        var unread: [FourCC: [String: Int]] = [:]
        var untallied: Set<FourCC> = []

        var unknownFieldTotal: Int {
            unread.values.flatMap(\.self)
                .filter { $0.key.hasPrefix("unknown ") }
                .reduce(0) { $0 + $1.value }
        }

        mutating func decode(_ record: ESMRecord, localized: Bool) {
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
                failures.append("\(record.type) \(FormID(record.formID)): \(error)")
            }
        }
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func decodesEveryRecordOfTheInstall() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        var sweep = Sweep()
        for name in try InstallPlugins.names(root: root) {
            let file = try ESMFile(url: root.dataURL.appending(path: name))
            sweep.decode(file.tes4, localized: file.isLocalized)
            ESMWalk.forEachRecord(in: file) { record in
                if !record.isDeleted {
                    sweep.decode(record, localized: file.isLocalized)
                }
                return true
            }
        }
        #expect(sweep.missing.isEmpty, "types with no decoder: \(sweep.missing)")
        #expect(sweep.failures.isEmpty, "records that threw: \(sweep.failures.prefix(10))")
        #expect(sweep.counts.count == 120, "record type count drift")
        #expect(sweep.counts.values.reduce(0, +) == Self.pinnedTotal, "record count drift")
        #expect(sweep.untallied.isEmpty, "types with no skip tally: \(sweep.untallied)")
        #expect(sweep.unknownFieldTotal == Self.pinnedUnknownFields, "unread field drift")
        Self.writeReport(sweep)
    }

    private static let pinnedTotal = 1_188_164
    /// Fields no decoder reads, summed over the install. docs/formats/records.md.
    private static let pinnedUnknownFields = 4893

    private static func writeReport(_ sweep: Sweep) {
        var lines = [
            "[INFO] records \(sweep.counts.values.reduce(0, +)), types \(sweep.counts.count)",
            "[INFO] failures \(sweep.failures.count)",
            "[INFO] unknown fields \(sweep.unknownFieldTotal)"
        ]
        lines += sweep.failures.prefix(50).map { "[ERROR] \($0)" }
        for (type, count) in sweep.counts.sorted(by: { $0.key.description < $1.key.description }) {
            lines.append("[INFO] \(type) \(count)")
            let ranked = (sweep.unread[type] ?? [:]).sorted { $0.value > $1.value }
            lines += ranked.map { "  unread \($0.key): \($0.value)" }
        }
        let report = lines.joined(separator: "\n")
        print(report)
        try? report.write(
            to: RepositoryLogs.directory().appending(path: "record-coverage-sweep.log"),
            atomically: true,
            encoding: .utf8
        )
    }
}
