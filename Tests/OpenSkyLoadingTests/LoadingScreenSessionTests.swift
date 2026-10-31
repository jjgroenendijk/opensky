// Loading-screen timing: a fast build still shows the minimum time, a slow
// build holds the screen until ready, and the player turns the object inside its range.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyLoading
import Testing

struct LoadingScreenSessionTests {
    private typealias Fixture = ESMFixture

    private static func screen(range: (UInt16, UInt16)?) throws -> ResolvedRecord<LoadScreen> {
        var fields: [(String, Data)] = [("RNAM", Fixture.u16(0, 0, 90))]
        if let range {
            fields.append(("ONAM", Fixture.u16(range.0, range.1)))
        }
        let record = try LoadScreen(
            record: Fixture.record("LSCR", fields: fields),
            localized: false
        )
        return ResolvedRecord(
            id: ResolvedFormID(plugin: "Base.esm", objectID: 0x10), record: record,
            sourcePlugin: "Base.esm"
        )
    }

    @Test func fastBuildStillShowsTheMinimumTime() {
        var session = LoadingScreenSession(screen: nil, startedAt: 10)
        session.markReady(at: 10.1)
        #expect(session.phase(at: 11) == .showing)
        #expect(session.phase(at: 10 + LoadingScreenSession.minimumSeconds + 0.1) == .fading)
        #expect(session.phase(at: 13) == .finished)
    }

    @Test func slowBuildHoldsUntilReady() {
        var session = LoadingScreenSession(screen: nil, startedAt: 0)
        #expect(session.phase(at: 30) == .showing)
        #expect(session.opacity(at: 30) == 1)
        session.markReady(at: 30)
        session.markReady(at: 40)
        #expect(session.readyAt == 30)
        #expect(session.phase(at: 30.2) == .fading)
        #expect(abs(session.opacity(at: 30.2) - 0.5) < 0.001)
        #expect(session.phase(at: 30.5) == .finished)
    }

    @Test func playerTurnStopsAtTheRangeEnds() throws {
        var session = try LoadingScreenSession(
            screen: Self.screen(range: (0xFFF6, 10)),
            startedAt: 0
        )
        #expect(session.objectRotationDegrees == [0, 0, 90])
        session.turn(byDegrees: 4)
        #expect(session.objectRotationDegrees == [0, 0, 94])
        session.turn(byDegrees: 30)
        #expect(session.objectRotationDegrees == [0, 0, 100])
        session.turn(byDegrees: -100)
        #expect(session.objectRotationDegrees == [0, 0, 80])
    }

    @Test func noRangeMeansNoTurn() throws {
        var session = try LoadingScreenSession(screen: Self.screen(range: nil), startedAt: 0)
        session.turn(byDegrees: 45)
        #expect(session.objectRotationDegrees == [0, 0, 90])
        #expect(session.elapsedSeconds(at: 50) == 50)
    }
}
