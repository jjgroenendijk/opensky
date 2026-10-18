// Tracked-stat events reach only the registered instance, once per changed stat, the
// rest events reach only a registered instance, and the state-change natives send their
// event to the actor's scripts.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusRegistrationEventTests {
    private typealias Fixture = PapyrusNativeReferenceFixture

    private static func incrementStat(_ fixture: Fixture, _ name: String, by amount: Int32 = 1) {
        let result = fixture.registry.invoke(PapyrusNativeCall(
            kind: .staticFunction, scriptName: "Game", functionName: "IncrementStat",
            receiver: nil, arguments: [.string(name), .integer(amount)], returnType: .none
        ))
        #expect(result == .returned(.none))
    }

    private static func instanceHandle(_ fixture: Fixture) throws -> PapyrusObjectHandle {
        try #require(fixture.session.world.instancesByKey[
            PapyrusInstanceKey(reference: fixture.key, scriptName: "Lever")
        ])
    }

    @Test func aRegisteredInstanceHearsEachChangedStat() throws {
        let fixture = try Fixture.make(events: [
            ("OnTrackedStatsEvent", PapyrusWorldFixture.probeBody(note: "stat"))
        ])
        let bridge = fixture.session.bridge
        bridge.queueTrackedStatEvents()
        let result = try fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "Form", "RegisterForTrackedStatsEvent", receiver: Self.instanceHandle(fixture)
        ))
        #expect(result == .returned(.none))
        Self.incrementStat(fixture, "Locks Picked")
        Self.incrementStat(fixture, "Bunnies Slaughtered", by: 2)
        #expect(bridge.queueTrackedStatEvents() == 2)
        #expect(bridge.queueTrackedStatEvents() == 0)
        PapyrusWorldFixture.drain(fixture.session.world)
        #expect(fixture.session.dispatch.notes == ["stat", "stat"])
    }

    @Test func aLoadIsNotReadAsStatChanges() throws {
        let fixture = try Fixture.make()
        let bridge = fixture.session.bridge
        bridge.queueTrackedStatEvents()
        fixture.session.world.trackedStatListeners.insert(
            PapyrusInstanceKey(reference: fixture.key, scriptName: "Lever")
        )
        Self.incrementStat(fixture, "Locks Picked")
        bridge.skipTrackedStatJournal()
        #expect(bridge.queueTrackedStatEvents() == 0)
    }

    @Test func theStateChangeNativesSendTheirEvent() throws {
        let fixture = try Fixture.make(events: [
            ("OnLycanthropyStateChanged", PapyrusWorldFixture.probeBody(note: "werewolf")),
            ("OnVampirismStateChanged", PapyrusWorldFixture.probeBody(note: "vampire"))
        ])
        for name in ["SendLycanthropyStateChanged", "SendVampirismStateChanged"] {
            let result = fixture.registry.invoke(PapyrusWorldFixture.methodCall(
                "Actor", name, receiver: fixture.receiver, arguments: [.boolean(true)]
            ))
            #expect(result == .returned(.none))
        }
        PapyrusWorldFixture.drain(fixture.session.world)
        #expect(fixture.session.dispatch.notes == ["werewolf", "vampire"])
    }

    @Test func onlyARegisteredInstanceHearsTheRestEvents() throws {
        let fixture = try Fixture.make(events: [
            ("OnSleepStart", PapyrusWorldFixture.probeBody(note: "start")),
            ("OnSleepStop", PapyrusWorldFixture.probeBody(note: "stop"))
        ])
        let world = fixture.session.world
        #expect(world.queueSleepEvents(start: 1, end: 1.25) == 0)
        let register = { (name: String) in
            try fixture.registry.invoke(PapyrusWorldFixture.methodCall(
                "Form", name, receiver: Self.instanceHandle(fixture)
            ))
        }
        #expect(try register("RegisterForSleep") == .returned(.none))
        #expect(world.queueSleepEvents(start: 1, end: 1.25) == 2)
        PapyrusWorldFixture.drain(world)
        #expect(fixture.session.dispatch.notes == ["start", "stop"])
        #expect(try register("UnregisterForSleep") == .returned(.none))
        #expect(world.queueSleepEvents(start: 2, end: 2.25) == 0)
    }
}
