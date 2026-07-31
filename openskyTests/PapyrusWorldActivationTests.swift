// Use-key activation reaching Papyrus (issue #172): the multicast interaction
// seam, the recorded `ReferenceActivationState`, the queued `OnActivate` with
// `akActionRef`, the player's reference key, the save round trip, and the
// activation recursion cap.
//
// Everything is synthetic — REFR bytes and PEX objects built in code — so the
// whole file runs with no game data and no GPU.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct PapyrusWorldActivationTests {
    // MARK: - Fixtures

    private static let doorID: UInt32 = 0x21
    private static let leverID: UInt32 = 0x22

    private static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: PapyrusWorldFixture.pluginName, objectID: objectID)
    }

    static func interaction(
        reference: UInt32,
        action: InteractionAction
    ) -> PlacedInteraction {
        PlacedInteraction(
            reference: FormID(reference),
            base: FormID(0x100),
            position: .zero,
            name: "Test Object",
            action: action,
            actionLabel: action == .open ? "Open" : "Activate",
            sounds: nil
        )
    }

    private static func event(
        reference: UInt32,
        action: InteractionAction = .open
    ) -> InteractionEvent {
        InteractionEvent(target: InteractionTarget(
            interaction: interaction(reference: reference, action: action),
            hitPosition: .zero,
            distance: 1
        ))
    }

    /// `OnActivate(ObjectReference akActionRef)` forwarding its activator to
    /// `Probe.Seen`, so a test can watch the exact handle script code sees.
    static func onActivateScript(_ name: String) -> PexObject {
        let body = PexFixture.runtimeFunction(
            parameters: [PexTypedName(name: "akActionRef", typeName: "ObjectReference")],
            instructions: [PapyrusTestSupport.instruction(
                .callStatic,
                .identifier("Probe"),
                .identifier("Seen"),
                .identifier("::nonevar"),
                .integer(1),
                .identifier("akActionRef")
            )]
        )
        return PapyrusWorldFixture.eventScript(name, events: [("OnActivate", body)])
    }

    private static func doorSession(
        scripts: [String]
    ) throws -> PapyrusWorldFixture.Session {
        try PapyrusWorldFixture.session(
            objects: scripts.map { onActivateScript($0) },
            entries: [PapyrusWorldFixture.referenceEntry(
                objectID: doorID,
                scripts: scripts.map { .init($0, properties: []) }
            )]
        )
    }

    // MARK: - Recording an activation

    @Test("an interaction event records an activation by the player")
    func interactionRecordsActivation() throws {
        let session = try Self.doorSession(scripts: ["DoorScript"])
        let outcome = session.bridge.handleInteraction(Self.event(reference: Self.doorID))

        #expect(outcome.recorded)
        #expect(outcome.cappedByRecursion == false)
        let activation = try #require(session.worldState.component(
            ReferenceActivationState.self, for: Self.key(Self.doorID)
        ))
        #expect(activation.activationCount == 1)
        #expect(activation.lastActivator == ReferenceKey.player)
        #expect(activation.lastActivator == session.bridge.playerKey)
        // A door-style `open` action is what toggles the open marker.
        #expect(activation.isOpen)
    }

    @Test("a non-door activation counts without toggling the open marker")
    func activateActionLeavesOpenAlone() throws {
        let session = try Self.doorSession(scripts: ["DoorScript"])
        session.bridge.handleInteraction(
            Self.event(reference: Self.doorID, action: .activate)
        )
        session.bridge.handleInteraction(
            Self.event(reference: Self.doorID, action: .activate)
        )

        let activation = try #require(session.worldState.component(
            ReferenceActivationState.self, for: Self.key(Self.doorID)
        ))
        #expect(activation.activationCount == 2)
        #expect(activation.isOpen == false)
    }

    @Test("the activation write is attributed to the reference's cell")
    func activationIsAttributedToItsCell() throws {
        let session = try Self.doorSession(scripts: ["DoorScript"])
        session.bridge.handleInteraction(Self.event(reference: Self.doorID))

        #expect(session.worldState.dirtyCount == 1)
        #expect(session.worldState.dirtyCount(in: PapyrusWorldFixture.cell) == 1)
        #expect(session.worldState.unattributedDirtyCount == 0)
        let entries = session.worldState.journalEntries
        #expect(entries.count == 1)
        #expect(entries.last?.kind == .activation)
        #expect(entries.last?.cell == PapyrusWorldFixture.cell)
        #expect(entries.last?.key == Self.key(Self.doorID))
    }

    @Test("a reference no resident cell knows records nothing")
    func unknownReferenceIsDropped() throws {
        let session = try Self.doorSession(scripts: ["DoorScript"])
        let outcome = session.bridge.handleInteraction(Self.event(reference: 0xFFF))

        #expect(outcome == .none)
        #expect(session.worldState.dirtyCount == 0)
        #expect(!session.world.eventQueue.contains { $0.functionName == "OnActivate" })
    }

    // MARK: - OnActivate

    @Test("OnActivate is queued once per attached script, with akActionRef")
    func onActivateQueuedPerScript() throws {
        let session = try Self.doorSession(scripts: ["AScript", "BScript"])
        PapyrusWorldFixture.drain(session.world)
        session.bridge.handleInteraction(Self.event(reference: Self.doorID))

        let playerHandle = session.world.objectHandle(for: .player)
        let queued = session.world.eventQueue
        #expect(queued.count == 2)
        #expect(queued.allSatisfy { $0.functionName == "OnActivate" })
        #expect(queued.allSatisfy { $0.arguments == [.object(playerHandle)] })
        #expect(queued.allSatisfy { $0.activationDepth == 1 })
        // Sorted instance order, so the queue is deterministic.
        #expect(queued.map(\.target.scriptName) == ["ascript", "bscript"])
        #expect(queued.allSatisfy { $0.target.reference == Self.key(Self.doorID) })
    }

    @Test("script code receives the player handle as akActionRef")
    func scriptSeesPlayerHandle() throws {
        let session = try Self.doorSession(scripts: ["DoorScript"])
        var seen: [PapyrusValue] = []
        session.dispatch.probeHandler = { call, _ in
            seen.append(contentsOf: call.arguments)
            return .returned(.none)
        }
        PapyrusWorldFixture.drain(session.world)
        session.bridge.handleInteraction(Self.event(reference: Self.doorID))
        PapyrusWorldFixture.drain(session.world)

        #expect(seen.count == 1)
        guard case let .object(handle) = seen.first else {
            Issue.record("akActionRef did not arrive as an object")
            return
        }
        #expect(session.world.referenceKey(for: handle) == ReferenceKey.player)
    }

    @Test("the player handle is stable and resolves back to the player key")
    func playerHandleIsStable() throws {
        let session = try Self.doorSession(scripts: ["DoorScript"])
        let first = session.world.objectHandle(for: .player)
        session.bridge.handleInteraction(Self.event(reference: Self.doorID))
        let second = session.world.objectHandle(for: .player)

        #expect(first == second)
        #expect(session.world.referenceKey(for: first) == ReferenceKey.player)
        // An opaque handle cannot collide with an instance handle.
        #expect(session.world.runtime.instance(for: first) == nil)
        #expect(!session.world.instancesByKey.values.contains(first))
        // A reference carrying a script answers with its instance handle.
        let doorHandle = session.world.objectHandle(for: Self.key(Self.doorID))
        #expect(session.world.instancesByKey.values.contains(doorHandle))
        #expect(session.world.referenceKey(for: doorHandle) == Self.key(Self.doorID))
    }

    @Test("a target with no scripts still records its activation")
    func scriptlessTargetRecordsActivation() throws {
        let session = try PapyrusWorldFixture.session(
            objects: [],
            entries: [PapyrusWorldFixture.referenceEntry(
                objectID: Self.leverID, scripts: []
            )]
        )
        let outcome = session.bridge.handleInteraction(Self.event(reference: Self.leverID))

        #expect(outcome.recorded)
        #expect(outcome.queuedEvents == 0)
        #expect(session.world.eventQueue.isEmpty)
        #expect(session.worldState.dirtyCount == 1)
    }

    // MARK: - Recursion cap

    @Test("a self-activating script chain is capped and tallied")
    func activationRecursionIsCapped() throws {
        let session = try Self.doorSession(scripts: ["DoorScript"])
        let door = Self.key(Self.doorID)
        // Stands in for the `Activate` native the next slice installs: every
        // OnActivate activates the same reference again.
        session.dispatch.probeHandler = { _, context in
            context.world?.activate(door, by: ReferenceKey.player, togglesOpen: false)
            return .returned(.none)
        }
        PapyrusWorldFixture.drain(session.world)
        session.bridge.handleInteraction(Self.event(reference: Self.doorID))
        PapyrusWorldFixture.drain(session.world)

        let tally = session.world.runtime.tally
        #expect(tally.activationRecursionCappedTotal == 1)
        #expect(session.world.eventQueue.isEmpty)
        let activation = try #require(session.worldState.component(
            ReferenceActivationState.self, for: door
        ))
        // One player activation plus one per dispatched OnActivate below the
        // cap; the capped one records nothing.
        #expect(activation.activationCount == UInt32(PapyrusWorldRuntime.maximumActivationDepth))
        #expect(session.world.currentActivationDepth == 0)
    }

    // MARK: - Save round trip

    @Test("activation count and the player activator round-trip the save")
    func activationRoundTripsTheSave() throws {
        let session = try Self.doorSession(scripts: ["DoorScript"])
        session.bridge.handleInteraction(Self.event(reference: Self.doorID))
        session.bridge.handleInteraction(Self.event(reference: Self.doorID))

        let encoded = OpenSkySaveEncoder.encode(
            snapshot: session.worldState.snapshot(),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
        let decoded = try OpenSkySaveDecoder.decode(encoded)
        let restored = WorldStateStore()
        restored.restore(from: decoded.snapshot)

        let activation = try #require(restored.component(
            ReferenceActivationState.self, for: Self.key(Self.doorID)
        ))
        #expect(activation.activationCount == 2)
        #expect(activation.lastActivator == ReferenceKey.player)
        #expect(activation.isOpen == false) // opened, then closed again
    }
}
