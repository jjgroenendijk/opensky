// M11 milestone engine acceptance (issue #174): a real PapyrusRuntime,
// WorldStateStore and CellStreamer activate a synthetic VMAD-bound lever, then
// OpenSkySaveStore restores its world mutation, script variable and pending
// timer into a fresh engine instance. No game bytes or test doubles are used.

import Foundation
@testable import opensky
import Testing

@MainActor
struct M11AcceptanceEngineTests {
    private static let slot = "m11-acceptance-engine"
    private static let timerInterval = 5.0

    @Test
    func activatedStateRoundTripsIntoAFreshEngineInstance() throws {
        let source = try M11ScriptedWorldChain()
        let instanceKey = PapyrusInstanceKey(
            reference: M11ScriptedWorldChain.leverKey,
            scriptName: "LeverScript"
        )
        let sourceHandle = try #require(source.session.world.instancesByKey[instanceKey])
        let sourceInstance = try #require(
            source.session.world.runtime.instance(for: sourceHandle)
        )
        #expect(sourceInstance.value(named: "activationMarker", declaredBy: "LeverScript")
            == .integer(1))
        source.session.world.registerUpdateTimer(
            handle: sourceHandle,
            slot: .realSingleShot,
            interval: Self.timerInterval
        )
        #expect(source.session.world.updateTimers.pendingCount == 1)

        let directory = try M10StateAcceptanceTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OpenSkySaveStore(directory: directory)
        try store.save(
            snapshot: source.session.worldState.snapshot(),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            scripts: source.session.world.instanceStates(),
            timers: source.session.world.timerStates(),
            toSlot: Self.slot
        )
        let file = try store.load(
            slot: Self.slot,
            verifyingAgainst: OpenSkySaveFixture.fingerprint
        )

        let fresh = try M11ScriptedWorldChain(activate: false)
        fresh.session.worldState.restore(from: file.snapshot)
        fresh.session.world.restore(instanceStates: file.scripts)
        fresh.session.world.restore(timerStates: file.timers)

        #expect(fresh.session.worldState.snapshot() == source.session.worldState.snapshot())
        #expect(fresh.session.worldState.journalEntries.isEmpty)
        let activation = try #require(fresh.session.worldState.component(
            ReferenceActivationState.self,
            for: M11ScriptedWorldChain.leverKey
        ))
        #expect(activation.activationCount == 1)
        #expect(activation.lastActivator == .player)
        #expect(fresh.session.worldState.component(
            ReferenceEnableState.self,
            for: M11ScriptedWorldChain.doorKey
        ) == .disabled)

        let freshHandle = try #require(fresh.session.world.instancesByKey[instanceKey])
        let freshInstance = try #require(
            fresh.session.world.runtime.instance(for: freshHandle)
        )
        #expect(freshInstance.value(named: "activationMarker", declaredBy: "LeverScript")
            == .integer(1))
        #expect(fresh.session.world.instanceStates() == source.session.world.instanceStates())
        #expect(fresh.session.world.timerStates() == source.session.world.timerStates())
        #expect(fresh.session.world.updateTimers.pendingCount == 1)
    }
}
