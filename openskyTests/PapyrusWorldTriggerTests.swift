// `OnTriggerEnter` / `OnTriggerLeave` dispatch (issue #173): queue shape, the
// player as `akActionRef`, the missing-handler no-op, the bridge seam, and the
// cell-unload containment ordering against `detach`.
//
// Synthetic PEX objects and synthetic REFR records only; the end-to-end walk
// lives in M11TriggerVolumeWalkTests.

@testable import opensky
import simd
import Testing

@MainActor
struct PapyrusWorldTriggerTests {
    static let scriptName = "TriggerScript"
    static let volumeID: UInt32 = 0x501

    static var volumeKey: ReferenceKey {
        TriggerStreamFixture.key(volumeID)
    }

    /// Script whose `OnTriggerEnter` and `OnTriggerLeave` record a note each.
    static func triggerScript(_ name: String = scriptName) -> PexObject {
        let key = PapyrusRuntime.key(name)
        return PapyrusWorldFixture.eventScript(name, events: [
            ("OnTriggerEnter", PapyrusWorldFixture.probeBody(note: "\(key).enter")),
            ("OnTriggerLeave", PapyrusWorldFixture.probeBody(note: "\(key).leave"))
        ])
    }

    /// Script that implements neither handler, so both queue and both are
    /// counted no-ops rather than faults.
    static func silentScript(_ name: String) -> PexObject {
        PapyrusWorldFixture.eventScript(name, events: [
            ("OnInit", PapyrusWorldFixture.probeBody(note: "silent.oninit"))
        ])
    }

    private static func session(
        scripts: [VMADFixture.Script],
        objects: [PexObject],
        isPersistent: Bool = false
    ) throws -> PapyrusWorldFixture.Session {
        let entry = try PapyrusWorldFixture.referenceEntry(
            objectID: volumeID, scripts: scripts, isPersistent: isPersistent
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
                VMADFixture.Script(Self.scriptName, properties: []),
                VMADFixture.Script("OtherTrigger", properties: [])
            ],
            objects: [Self.triggerScript(), Self.triggerScript("OtherTrigger")]
        )
        let queued = session.world.queueOnTriggerEnter(
            volume: Self.volumeKey, actor: .player
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
            scripts: [VMADFixture.Script(Self.scriptName, properties: [])],
            objects: [Self.triggerScript()]
        )
        #expect(session.world.queueOnTriggerLeave(
            volume: Self.volumeKey, actor: .player
        ) == 1)
        #expect(session.world.eventQueue.first?.functionName == "OnTriggerLeave")
        #expect(PapyrusWorldRuntime.onTriggerEnterEventName == "OnTriggerEnter")
        #expect(PapyrusWorldRuntime.onTriggerLeaveEventName == "OnTriggerLeave")
    }

    @Test
    func aVolumeWithNoScriptsQueuesNothing() throws {
        let session = try Self.session(
            scripts: [VMADFixture.Script(Self.scriptName, properties: [])],
            objects: [Self.triggerScript()]
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
            objects: [Self.silentScript("SilentScript")]
        )
        session.world.queueOnTriggerEnter(volume: Self.volumeKey, actor: .player)
        session.world.queueOnTriggerLeave(volume: Self.volumeKey, actor: .player)
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
            scripts: [VMADFixture.Script(Self.scriptName, properties: [])],
            objects: [Self.triggerScript()]
        )
        #expect(session.bridge.handleTriggerTransition(
            TriggerTransitionEvent(reference: Self.volumeKey, phase: .enter)
        ) == 1)
        #expect(session.bridge.handleTriggerTransition(
            TriggerTransitionEvent(reference: Self.volumeKey, phase: .leave)
        ) == 1)
        PapyrusWorldFixture.drain(session.world)
        let key = PapyrusRuntime.key(Self.scriptName)
        #expect(session.dispatch.notes == ["\(key).enter", "\(key).leave"])
    }
}
