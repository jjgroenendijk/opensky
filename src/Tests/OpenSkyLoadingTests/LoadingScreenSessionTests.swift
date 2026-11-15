// Loading-screen timing: a fast build still shows the minimum time, a slow
// build holds the screen until ready, and the player turns and zooms inside the limits.

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
        #expect(session.phase(at: 13.1) == .finished)
    }

    @Test func slowBuildHoldsUntilReady() {
        var session = LoadingScreenSession(screen: nil, startedAt: 0)
        #expect(session.phase(at: 30) == .showing)
        #expect(session.opacity(at: 30) == 1)
        session.markReady(at: 30)
        session.markReady(at: 40)
        #expect(session.readyAt == 30)
        #expect(session.phase(at: 30.5) == .fading)
        #expect(abs(session.opacity(at: 30.5) - 0.5) < 0.001)
        #expect(session.phase(at: 31) == .finished)
    }

    @Test func playerTurnStopsAtTheRangeEnds() throws {
        var session = try LoadingScreenSession(
            screen: Self.screen(range: (0xFFF6, 10)),
            startedAt: 0
        )
        #expect(session.initialRotationDegrees == [0, 0, 90])
        session.turn(byRadians: 0.1)
        #expect(abs(session.turnRadians - 0.1) < 1e-6)
        session.turn(byRadians: 1)
        #expect(abs(session.turnDegrees - 10) < 1e-4)
        session.turn(byRadians: -2)
        #expect(abs(session.turnDegrees + 10) < 1e-4)
    }

    @Test func noRangeOrAFullRangeTurnsFreely() throws {
        for range in [nil, (UInt16(0xFF4C), UInt16(180))] {
            var session = try LoadingScreenSession(screen: Self.screen(range: range), startedAt: 0)
            session.turn(byRadians: 4)
            session.turn(byRadians: 4)
            #expect(session.turnRadians == 8)
        }
        let session = try LoadingScreenSession(screen: Self.screen(range: nil), startedAt: 0)
        #expect(session.elapsedSeconds(at: 50) == 50)
    }

    @Test func aZoomOutsideTheOpenLimitsIsIgnored() {
        var session = LoadingScreenSession(screen: nil, startedAt: 0)
        #expect(session.fieldOfView == 75)
        session.changeFieldOfView(by: 15)
        #expect(session.fieldOfView == 90)
        session.changeFieldOfView(by: 5)
        #expect(session.fieldOfView == 90, "95 is outside the open range")
        session.changeFieldOfView(by: -29)
        #expect(session.fieldOfView == 61)
        session.changeFieldOfView(by: -1)
        #expect(session.fieldOfView == 61, "60 is outside the open range")
    }
}
