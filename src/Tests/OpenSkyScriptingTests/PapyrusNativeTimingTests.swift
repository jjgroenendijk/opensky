// Native timing under `PapyrusNativeTimingMode.game`: a delayed native returns on the
// next fixed step and releases its instance, a non-delayed one returns at once.

import Foundation
import OpenSkyFormatsPEX
@testable import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNativeTimingTests {
    private static let callCount = 5
    private static let key = PapyrusWorldFixture.key(objectID: 1, script: "TimingScript")

    @Test("the table follows the wiki categories and folds case")
    func tableClassifiesNatives() {
        #expect(PapyrusNativeTimingTable
            .timing(scriptName: "math", functionName: "ABS") == .nonDelayed)
        #expect(PapyrusNativeTimingTable
            .timing(scriptName: "Utility", functionName: "Wait") == .latent)
        #expect(
            PapyrusNativeTimingTable.timing(scriptName: "Actor", functionName: "GetActorValue")
                == .delayed
        )
        #expect(
            PapyrusNativeTimingTable.timing(scriptName: "Utility", functionName: "RandomInt")
                == .delayed
        )
    }

    @Test("N delayed calls in a row finish N steps after the event starts")
    func delayedCallsTakeOneStepEach() throws {
        let probe = PapyrusWorldProbeDispatch()
        let body = Self.repeated(Self.randomInt, then: "done")
        let world = try Self.world(onLoad: body, probe: probe, timing: .game)

        world.stepFixed()
        for _ in 1 ..< Self.callCount {
            #expect(probe.notes.isEmpty)
            world.stepFixed()
        }
        #expect(probe.notes.isEmpty)
        world.stepFixed()
        #expect(probe.notes == ["done"])
        #expect(world.lastStepDelayedCalls == 1)
    }

    @Test("N non-delayed calls in a row finish in the step the event starts")
    func nonDelayedCallsFinishAtOnce() throws {
        let probe = PapyrusWorldProbeDispatch()
        let body = Self.repeated(Self.mathAbs, then: "done")
        let world = try Self.world(onLoad: body, probe: probe, timing: .game)

        world.stepFixed()
        #expect(probe.notes == ["done"])
    }

    @Test("run-to-end timing finishes delayed calls in one step")
    func runToEndSkipsTheDelay() throws {
        let probe = PapyrusWorldProbeDispatch()
        let body = Self.repeated(Self.randomInt, then: "done")
        let world = try Self.world(onLoad: body, probe: probe, timing: .runToEnd)

        world.stepFixed()
        #expect(probe.notes == ["done"])
        #expect(world.lastStepDelayedCalls == 0)
    }

    @Test("a state change after an external call races with the next event")
    func stateChangeAfterTheCallRaces() throws {
        let probe = PapyrusWorldProbeDispatch()
        let guarded = Self.activateHandler(gotoStateFirst: false)
        let world = try Self.raceWorld(handler: guarded, probe: probe)

        PapyrusWorldFixture.drain(world)
        #expect(probe.notes == ["enter", "enter"])
    }

    @Test("GotoState before the external call keeps the next event out")
    func gotoStateBeforeTheCallGuards() throws {
        let probe = PapyrusWorldProbeDispatch()
        let guarded = Self.activateHandler(gotoStateFirst: true)
        let world = try Self.raceWorld(handler: guarded, probe: probe)

        PapyrusWorldFixture.drain(world)
        #expect(probe.notes == ["enter", "refused"])
    }

    @Test("WaitMenuMode counts menu time and Wait does not")
    func onlyWaitMenuModeCountsMenuTime() throws {
        var notes: [String: [String]] = [:]
        for wait in ["Wait", "WaitMenuMode"] {
            let probe = PapyrusWorldProbeDispatch()
            let call = PapyrusTestSupport.instruction(
                .callStatic, .identifier("Utility"), .identifier(wait),
                .identifier("::nonevar"), .integer(1), .float(0.1)
            )
            let body = PexFixture.runtimeFunction(instructions: [call, Self.note("done")])
            let world = try Self.world(onLoad: body, probe: probe, timing: .runToEnd)
            world.stepFixed()
            for _ in 0 ..< 10 {
                world.stepMenuTime()
            }
            notes[wait] = probe.notes
        }
        #expect(notes["Wait"]?.isEmpty == true)
        #expect(notes["WaitMenuMode"] == ["done"])
    }

    // MARK: Fixtures

    private static let randomInt = PapyrusTestSupport.instruction(
        .callStatic, .identifier("Utility"), .identifier("RandomInt"),
        .identifier("::nonevar"), .integer(2), .integer(0), .integer(1)
    )

    private static let mathAbs = PapyrusTestSupport.instruction(
        .callStatic, .identifier("Math"), .identifier("Abs"),
        .identifier("::nonevar"), .integer(1), .float(-1)
    )

    private static func note(_ text: String) -> PexInstruction {
        PapyrusTestSupport.instruction(
            .callStatic, .identifier("Probe"), .identifier("Note"),
            .identifier("::nonevar"), .integer(1), .string(text)
        )
    }

    private static func gotoState(_ name: String) -> PexInstruction {
        PapyrusTestSupport.instruction(
            .callMethod, .identifier("GotoState"), .identifier("self"),
            .identifier("::nonevar"), .integer(1), .string(name)
        )
    }

    private static func repeated(_ call: PexInstruction, then text: String) -> PexFunction {
        PexFixture.runtimeFunction(
            instructions: Array(repeating: call, count: callCount) + [note(text)]
        )
    }

    /// `OnActivate` in the empty state notes "enter", makes a delayed call, and moves to
    /// "Busy". In "Busy" it notes "refused".
    private static func activateHandler(gotoStateFirst: Bool) -> PexObject {
        let work = [note("enter"), randomInt]
        let instructions = gotoStateFirst
            ? [gotoState("Busy")] + work
            : work + [gotoState("Busy")]
        return PexFixture.runtimeObject(
            name: "TimingScript",
            states: [
                PapyrusTestSupport.state(functions: [
                    ("OnActivate", PexFixture.runtimeFunction(instructions: instructions))
                ]),
                PapyrusTestSupport.state("Busy", functions: [
                    ("OnActivate", PexFixture.runtimeFunction(instructions: [note("refused")]))
                ])
            ]
        )
    }

    private static func raceWorld(
        handler: PexObject,
        probe: PapyrusWorldProbeDispatch
    ) throws -> PapyrusWorldRuntime {
        let world = try attached(handler, probe: probe, timing: .game)
        let activate = PapyrusScriptEvent(target: key, functionName: "OnActivate", arguments: [])
        world.eventQueue = [activate, activate]
        return world
    }

    private static func world(
        onLoad body: PexFunction,
        probe: PapyrusWorldProbeDispatch,
        timing: PapyrusNativeTimingMode
    ) throws -> PapyrusWorldRuntime {
        let script = PapyrusWorldFixture.eventScript("TimingScript", events: [("OnLoad", body)])
        let world = try attached(script, probe: probe, timing: timing)
        world.eventQueue = [PapyrusScriptEvent(target: key, functionName: "OnLoad", arguments: [])]
        return world
    }

    private static func attached(
        _ script: PexObject,
        probe: PapyrusWorldProbeDispatch,
        timing: PapyrusNativeTimingMode
    ) throws -> PapyrusWorldRuntime {
        let world = PapyrusWorldFixture.worldRuntime(objects: [script], nativeDispatch: probe)
        world.runtime.nativeTiming = timing
        try world.attach(
            cell: PapyrusWorldFixture.cell,
            references: PapyrusWorldFixture.index([PapyrusWorldFixture.referenceEntry(
                objectID: 1, scripts: [.init("TimingScript", properties: [])]
            )]),
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        return world
    }
}
