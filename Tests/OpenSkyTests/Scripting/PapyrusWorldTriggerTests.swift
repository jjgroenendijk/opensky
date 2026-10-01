// `OnTriggerEnter` and `OnTriggerLeave` dispatch: queue shape, the player as
// `akActionRef`, missing handlers, the bridge, and unload order against
// `detach`. The end-to-end walk is in M11TriggerVolumeWalkTests.

import FormatsESMTesting
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsPEX
@testable import OpenSkyPhysics
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import simd
import Testing

@MainActor
struct PapyrusWorldTriggerTests {
    private static func session(
        scripts: [VMADFixture.Script],
        objects: [PexObject],
        isPersistent: Bool = false
    ) throws -> PapyrusWorldFixture.Session {
        let entry = try PapyrusWorldFixture.referenceEntry(
            objectID: TriggerStreamFixture.volumeID, scripts: scripts, isPersistent: isPersistent
        )
        let session = PapyrusWorldFixture.session(objects: objects, entries: [entry])
        PapyrusWorldFixture.drain(session.world)
        return session
    }

    // MARK: - Queue shape

    @Test
    func enterQueuesOneEventPerScriptWithThePlayerAsActionRef() throws {
        let session = try Self.session(
            scripts: [
                VMADFixture.Script(TriggerStreamFixture.scriptName, properties: []),
                VMADFixture.Script("OtherTrigger", properties: [])
            ],
            objects: [
                TriggerStreamFixture.triggerScript(),
                TriggerStreamFixture.triggerScript("OtherTrigger")
            ]
        )
        let queued = session.world.queueOnTriggerEnter(
            volume: TriggerStreamFixture.volumeKey, actor: .player
        )
        #expect(queued == 2)
        let events = session.world.eventQueue
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.functionName == "OnTriggerEnter" })
        // Trigger edges are not activation chains, so they never consume the
        // recursion cap.
        #expect(events.allSatisfy { $0.activationDepth == 0 })
        // Deterministic instance order: ascending PapyrusInstanceKey.
        #expect(events.map(\.target) == events.map(\.target).sorted())
        let handle = session.world.objectHandle(for: .player)
        #expect(events.allSatisfy { $0.arguments == [.object(handle)] })
        #expect(session.world.referenceKey(for: handle) == .player)
    }

    @Test
    func leaveQueuesTheMatchingEventName() throws {
        let session = try Self.session(
            scripts: [VMADFixture.Script(TriggerStreamFixture.scriptName, properties: [])],
            objects: [TriggerStreamFixture.triggerScript()]
        )
        #expect(session.world.queueOnTriggerLeave(
            volume: TriggerStreamFixture.volumeKey, actor: .player
        ) == 1)
        #expect(session.world.eventQueue.first?.functionName == "OnTriggerLeave")
        #expect(PapyrusWorldRuntime.onTriggerEnterEventName == "OnTriggerEnter")
        #expect(PapyrusWorldRuntime.onTriggerLeaveEventName == "OnTriggerLeave")
    }

    @Test
    func aVolumeWithNoScriptsQueuesNothing() throws {
        let session = try Self.session(
            scripts: [VMADFixture.Script(TriggerStreamFixture.scriptName, properties: [])],
            objects: [TriggerStreamFixture.triggerScript()]
        )
        let queued = session.world.queueOnTriggerEnter(
            volume: TriggerStreamFixture.key(0x999), actor: .player
        )
        #expect(queued == 0)
        #expect(session.world.eventQueue.isEmpty)
    }

    @Test
    func aScriptWithoutTheHandlerIsACountedNoOpAndNotAFault() throws {
        let session = try Self.session(
            scripts: [VMADFixture.Script("SilentScript", properties: [])],
            objects: [TriggerStreamFixture.silentScript("SilentScript")]
        )
        session.world.queueOnTriggerEnter(volume: TriggerStreamFixture.volumeKey, actor: .player)
        session.world.queueOnTriggerLeave(volume: TriggerStreamFixture.volumeKey, actor: .player)
        let before = session.world.skips.counts[.undefinedEventFunction] ?? 0
        PapyrusWorldFixture.drain(session.world)
        let after = session.world.skips.counts[.undefinedEventFunction] ?? 0
        #expect(after - before == 2)
        #expect(session.dispatch.notes == ["silent.oninit"])
    }

    // MARK: - Bridge seam

    @Test
    func theBridgeTurnsAnOccupancyEdgeIntoQueuedEvents() throws {
        let session = try Self.session(
            scripts: [VMADFixture.Script(TriggerStreamFixture.scriptName, properties: [])],
            objects: [TriggerStreamFixture.triggerScript()]
        )
        #expect(session.bridge.handleTriggerTransition(
            TriggerTransitionEvent(reference: TriggerStreamFixture.volumeKey, phase: .enter)
        ) == 1)
        #expect(session.bridge.handleTriggerTransition(
            TriggerTransitionEvent(reference: TriggerStreamFixture.volumeKey, phase: .leave)
        ) == 1)
        PapyrusWorldFixture.drain(session.world)
        let key = PapyrusRuntime.key(TriggerStreamFixture.scriptName)
        #expect(session.dispatch.notes == ["\(key).enter", "\(key).leave"])
    }
}
