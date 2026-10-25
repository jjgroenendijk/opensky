// Whole-install coverage: every live record in the five masters and the
// Creation Club plugins decodes through `RecordDecoders`. A type with no
// decoder, a decode that throws, or a decoder with no skip tally fails the sweep.
// Run with `make test-real T='RecordCoverageRealDataTests'`.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.smoke))
struct RecordCoverageRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func decodesEveryRecordOfTheInstall() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        var sweep = RecordCoverageSweep()
        for name in try InstallPlugins.names(root: root) {
            try sweep.sweep(ESMFile(url: root.dataURL.appending(path: name)))
        }
        #expect(sweep.missing.isEmpty, "types with no decoder: \(sweep.missing)")
        #expect(sweep.failures.isEmpty, "records that threw: \(sweep.failures.prefix(10))")
        #expect(
            ContentCount.isNear(sweep.counts.count, Self.baselineTypes),
            "record type count drift"
        )
        #expect(ContentCount.isNear(sweep.recordTotal, Self.baselineTotal), "record count drift")
        #expect(sweep.untallied.isEmpty, "types with no skip tally: \(sweep.untallied)")
        #expect(sweep.unknownFieldTotal == Self.pinnedUnknownFields, "unread field drift")
        Self.writeReport(sweep)
    }

    private static let baselineTypes = 120
    private static let baselineTotal = 1_188_164

    /// Fields no decoder reads, summed over the install. docs/formats/records.md.
    private static let pinnedUnknownFields = 0

    private static func writeReport(_ sweep: RecordCoverageSweep) {
        var lines = [
            "[INFO] records \(sweep.recordTotal), types \(sweep.counts.count)",
            "[INFO] failures \(sweep.failureCounts.values.reduce(0, +))",
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
