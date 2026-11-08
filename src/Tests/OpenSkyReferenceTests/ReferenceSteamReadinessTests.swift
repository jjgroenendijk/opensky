// When a newly started Steam can take the game, read from its logs on a temporary prefix.

import Foundation
@testable import OpenSkyReference
import Testing

struct ReferenceSteamReadinessTests {
    private func makePrefix() throws -> ReferencePrefix {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ReferenceSteamReadinessTests-\(UUID())", directoryHint: .isDirectory)
        let prefix = ReferencePrefix(root: root)
        try FileManager.default.createDirectory(
            at: ReferenceSteamReadiness.consoleLog(prefix).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return prefix
    }

    private func append(_ line: String, to url: URL) throws {
        let old = (try? Data(contentsOf: url)) ?? Data()
        try (old + Data((line + "\n").utf8)).write(to: url)
    }

    @Test func steamIsReadyOnceItStartedAndLoggedOn() {
        let started = "[2026-11-01 13:50:13] System startup time: 23.20 seconds"
        let loggedOn = "[Logged On, 4, 7] RecvMsgClientLogOnResponse() : processing complete"
        #expect(!ReferenceSteamReadiness.isReady(console: started, connection: ""))
        #expect(!ReferenceSteamReadiness.isReady(console: "", connection: loggedOn))
        #expect(ReferenceSteamReadiness.isReady(console: started, connection: loggedOn))
    }

    /// The logs keep earlier starts, so only lines after the mark count.
    @Test func linesFromAnEarlierStartDoNotCount() throws {
        let prefix = try makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix.root) }
        let console = ReferenceSteamReadiness.consoleLog(prefix)
        let connection = ReferenceSteamReadiness.connectionLog(prefix)
        try append("System startup time: 11.82 seconds", to: console)
        try append("RecvMsgClientLogOnResponse() : processing complete", to: connection)
        let readiness = ReferenceSteamReadiness.mark(prefix)
        #expect(!readiness.isReady(prefix))
        try append("System startup time: 23.20 seconds", to: console)
        #expect(!readiness.isReady(prefix))
        try append("RecvMsgClientLogOnResponse() : processing complete", to: connection)
        #expect(readiness.isReady(prefix))
    }

    @Test func aLogStartedAgainCountsFromItsStart() throws {
        let prefix = try makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix.root) }
        let readiness = ReferenceSteamReadiness(consoleOffset: 10000, connectionOffset: 10000)
        try append("System startup time: 5 seconds", to: ReferenceSteamReadiness.consoleLog(prefix))
        try append(
            "RecvMsgClientLogOnResponse() : processing complete",
            to: ReferenceSteamReadiness.connectionLog(prefix)
        )
        #expect(readiness.isReady(prefix))
    }
}
