import Foundation
@testable import OpenSkyFormatsCore
import TagsTesting
import Testing

@Suite(.serialized, .tags(.parser))
struct EngineLoggerTests {
    private func drained(_ category: String) -> [String] {
        EngineLogTap.drain().filter { $0.category == category }.map(\.message)
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

    @Test func tapKeepsOnlyTheNewestLines() {
        let category = "EngineLoggerTests-\(UUID())"
        let logger = EngineLogger(subsystem: "nl.jjgroenendijk.opensky.tests", category: category)
        for index in 0 ..< EngineLogTap.limit + 3 {
            logger.error("\(index)")
        }
        let lines = drained(category)
        #expect(lines.count == EngineLogTap.limit)
        #expect(lines.first == "3")
    }
}
