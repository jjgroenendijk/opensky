// What a headless sweep reads from the runtime: the named fallbacks, a bounded drain, the
// waiting calls dropped between subjects, and a stage's fragments queued on their own.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsPEX
@testable import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusHeadlessRunTests {
    private static let waiterKey = PapyrusWorldFixture.key(objectID: 1, script: "WaiterScript")

    private func waiterWorld(probe: PapyrusWorldProbeDispatch) throws -> PapyrusWorldRuntime {
        let waiter = PapyrusWorldFixture.eventScript("WaiterScript", events: [
            ("OnLoad", PapyrusWorldFixture.probeBody(note: "waiter.done", waitSeconds: 2))
        ])
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [waiter], nativeDispatch: probe, fixedStepSeconds: 1
        )
        try world.attach(
            cell: PapyrusWorldFixture.cell,
            references: PapyrusWorldFixture.index([PapyrusWorldFixture.referenceEntry(
                objectID: 1, scripts: [.init("WaiterScript", properties: [])]
            )]),
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        world.eventQueue = [
            PapyrusScriptEvent(target: Self.waiterKey, functionName: "OnLoad", arguments: [])
        ]
        return world
    }

    @Test func drainRunsALatentWaitToItsEnd() throws {
        let probe = PapyrusWorldProbeDispatch()
        let world = try waiterWorld(probe: probe)

        #expect(!world.drain(maxSteps: 2))
        #expect(world.drain())
        #expect(probe.notes == ["waiter.done"])
    }

    @Test func droppedWaitingCallsNeverResume() throws {
        let probe = PapyrusWorldProbeDispatch()
        let world = try waiterWorld(probe: probe)

        #expect(!world.drain(maxSteps: 1))
        world.dropWaitingCalls()
        #expect(world.drain())
        #expect(probe.notes.isEmpty)
    }

    @Test func fallbacksNameAnEventWithNoHandler() throws {
        let world = try waiterWorld(probe: PapyrusWorldProbeDispatch())
        world.eventQueue = [
            PapyrusScriptEvent(target: Self.waiterKey, functionName: "OnReset", arguments: [])
        ]
        world.drain()

        #expect(world.fallbacks.contains { $0.name.hasPrefix("script skip ") })
    }

    @Test func aStageWithNoFragmentQueuesNothing() throws {
        var fields = QuestFixture.editorID("NoFragments")
        fields += QuestFixture.stage(10)
        let quest = try QuestFixture.quest(fields: fields)
        let world = try waiterWorld(probe: PapyrusWorldProbeDispatch())

        #expect(world.queueStageFragments(
            of: quest, stage: 10, key: .plugin(name: "skyrim.esm", objectID: 0x800)
        ) == 0)
    }

    @Test func aNativeAnsweringNoneForATypedReturnIsNamed() {
        var registry = PapyrusNativeRegistry()
        registry.register(PapyrusNativeFunction(
            scriptName: "Probe", functionName: "Find", body: { _, _ in .returned(.none) }
        ))
        let native = PexFixture.runtimeFunction(
            returnType: "ObjectReference", flags: .native, instructions: []
        )
        let script = PexFixture.runtimeObject(
            name: "Probe", states: [PapyrusTestSupport.state(functions: [("Find", native)])]
        )
        let runtime = PapyrusRuntime(
            files: [PexFixture.runtimeFile(objects: [script])], nativeDispatch: registry
        )

        _ = runtime.invokeStatic("Find", on: "Probe")
        #expect(runtime.tally.fallbacks.contains { $0.name == "None from native Probe.Find" })
    }
}
