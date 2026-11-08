import Foundation
@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct EngineLoggerTests {
    private func drained(_ category: String) -> [String] {
        EngineLogTap.drain(category: category).map(\.message)
    }

    @Test func tapKeepsErrorAndFaultLinesOnly() {
        let category = "EngineLoggerTests-\(UUID())"
        let logger = EngineLogger(subsystem: "nl.jjgroenendijk.opensky.tests", category: category)
        logger.info("info line")
        logger.warning("warning line")
        logger.error("error \(42, privacy: .public)")
        logger.fault("fault \("text")")
        #expect(drained(category) == ["error 42", "fault text"])
        #expect(drained(category).isEmpty)
    }

    @Test func ringKeepsOnlyTheNewestLines() {
        var ring = EngineLogRing(limit: 4)
        for index in 0 ..< 7 {
            ring.append(EngineLogLine(category: "c", message: "\(index)"))
        }
        #expect(ring.drain(category: nil).map(\.message) == ["3", "4", "5", "6"])
        #expect(ring.drain(category: nil).isEmpty)
    }

    @Test func drainingOneCategoryKeepsTheOthers() {
        var ring = EngineLogRing(limit: 4)
        ring.append(EngineLogLine(category: "a", message: "1"))
        ring.append(EngineLogLine(category: "b", message: "2"))
        #expect(ring.drain(category: "a").map(\.message) == ["1"])
        #expect(ring.drain(category: nil).map(\.message) == ["2"])
    }
}
