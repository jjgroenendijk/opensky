// The repeating `OnTrigger` while the player stands in a trigger volume.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyPhysics
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusWorldTriggerRepeatTests {
    private static func fixture() throws -> PapyrusNativeReferenceFixture {
        try PapyrusNativeReferenceFixture.make(events: [
            ("OnTrigger", PapyrusWorldFixture.probeBody(note: "ontrigger"))
        ])
    }

    private static func count(_ fixture: PapyrusNativeReferenceFixture) -> Int {
        PapyrusWorldFixture.drain(fixture.session.world)
        return fixture.session.dispatch.notes.filter { $0 == "ontrigger" }.count
    }

    @Test func repeatsTwiceASecondWhileInsideAndStopsOnLeave() throws {
        let fixture = try Self.fixture()
        let bridge = fixture.session.bridge
        bridge.handleTriggerTransition(TriggerTransitionEvent(
            reference: fixture.key,
            phase: .enter
        ))
        bridge.queueTriggerRepeats(after: 0.3)
        #expect(Self.count(fixture) == 0)
        bridge.queueTriggerRepeats(after: 0.3)
        #expect(Self.count(fixture) == 1)
        bridge.queueTriggerRepeats(after: 0.5)
        #expect(Self.count(fixture) == 2)

        bridge.handleTriggerTransition(TriggerTransitionEvent(
            reference: fixture.key,
            phase: .leave
        ))
        bridge.queueTriggerRepeats(after: 1)
        #expect(Self.count(fixture) == 2)
    }

    @Test func anUnrunRepeatIsNotQueuedAgain() throws {
        let fixture = try Self.fixture()
        let bridge = fixture.session.bridge
        bridge.handleTriggerTransition(TriggerTransitionEvent(
            reference: fixture.key,
            phase: .enter
        ))
        bridge.queueTriggerRepeats(after: 0.5)
        bridge.queueTriggerRepeats(after: 0.5)
        #expect(fixture.session.world.eventQueue.filter { $0.functionName == "OnTrigger" }
            .count == 1)
    }
}
