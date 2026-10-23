// The engine event senders added for wards, books, grabs, traps, and bleedout, over a
// synthetic lever whose script handles each event.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import Testing

@MainActor
struct PapyrusEngineEventSenderTests {
    private typealias Fixture = PapyrusNativeReferenceFixture

    private static func fixture(_ events: [String]) throws -> Fixture {
        try Fixture.make(events: events.map {
            ($0, PapyrusWorldFixture.probeBody(note: $0.lowercased()))
        })
    }

    private static func run(_ fixture: Fixture, _ send: (PapyrusWorldRuntime) -> Void) -> [String] {
        let before = fixture.session.dispatch.notes.count
        send(fixture.session.world)
        PapyrusWorldFixture.drain(fixture.session.world)
        return Array(fixture.session.dispatch.notes.dropFirst(before))
    }

    @Test func aWardHitReachesTheHolder() throws {
        let fixture = try Self.fixture(["OnWardHit"])
        let door = Fixture.key(Fixture.doorID)
        let notes = Self.run(fixture) {
            $0.queueWardHit(holder: fixture.key, caster: door, spell: door, status: 1)
        }
        #expect(notes == ["onwardhit"])
    }

    @Test func readingGrabbingAndReleasingQueueTheirEvents() throws {
        let fixture = try Self.fixture(["OnRead", "OnGrab", "OnRelease"])
        #expect(Self.run(fixture) { $0.queueRead(on: fixture.key) } == ["onread"])
        #expect(Self.run(fixture) { $0.queueGrab(of: fixture.key, held: true) } == ["ongrab"])
        #expect(Self.run(fixture) { $0.queueGrab(of: fixture.key, held: false) } == ["onrelease"])
    }

    @Test func theFirstTrapHitAlsoStartsContact() throws {
        let fixture = try Self.fixture(["OnTrapHitStart", "OnTrapHit", "OnTrapHitStop"])
        #expect(fixture.session.world.handlesTrapHits(on: fixture.key))
        let door = Fixture.key(Fixture.doorID)
        let first = PapyrusTrapHit(
            target: door,
            velocity: [1, 0, 0],
            position: .zero,
            initial: true
        )
        let firstNotes = Self.run(fixture) { $0.queueTrapHit(first, on: fixture.key) }
        #expect(firstNotes.sorted() == ["ontraphit", "ontraphitstart"])
        let next = PapyrusTrapHit(
            target: door,
            velocity: [1, 0, 0],
            position: .zero,
            initial: false
        )
        #expect(Self.run(fixture) { $0.queueTrapHit(next, on: fixture.key) } == ["ontraphit"])
        #expect(Self.run(fixture) { $0.queueTrapHitStop(target: door, on: fixture.key) }
            == ["ontraphitstop"])
    }

    @Test func aTrapWithoutHandlersIsSkipped() throws {
        let fixture = try Self.fixture(["OnRead"])
        #expect(!fixture.session.world.handlesTrapHits(on: fixture.key))
    }

    @Test func bleedingOutReachesTheActor() throws {
        let fixture = try Self.fixture(["OnEnterBleedout"])
        #expect(Self
            .run(fixture) { $0.queueEnterBleedout(actor: fixture.key) } == ["onenterbleedout"])
    }

    @Test func theNewSendersAreInTheCensus() {
        let names = [
            PapyrusEngineEvents.onWardHit, PapyrusEngineEvents.onRead, PapyrusEngineEvents.onGrab,
            PapyrusEngineEvents.onRelease, PapyrusEngineEvents.onTrapHitStart,
            PapyrusEngineEvents.onTrapHit, PapyrusEngineEvents.onTrapHitStop,
            PapyrusEngineEvents.onEnterBleedout
        ]
        for name in names {
            #expect(PapyrusEventCensus.isSent(name), "\(name)")
        }
    }
}
