// The instruction budget every script shares per fixed step: busy loops stay inside it
// and each one moves, and a loop that waits costs almost nothing.

@testable import FormatsTesting
import Foundation
import OpenSkyFormatsPEX
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusWorldStepBudgetTests {
    @Test("busy loops share the step budget, and every loop moves")
    func busyLoopsShareTheBudget() throws {
        let names = ["SpinA", "SpinB", "SpinC", "SpinD"]
        let probe = PapyrusWorldProbeDispatch()
        let world = try Self.world(
            scripts: names.map { ($0, Self.busyLoop(note: $0)) }, probe: probe
        )
        world.budget = PapyrusTickBudget(events: 32, instructions: 50)

        for _ in 0 ..< 12 {
            world.stepFixed()
            #expect(world.lastStepInstructions <= 50)
        }
        #expect(world.runtime.tally.instructionsExecuted <= 12 * 50)
        for name in names {
            #expect(probe.notes.contains(name), "\(name) never ran")
        }
    }

    @Test("a loop that waits costs almost nothing, even beside busy loops")
    func waitingLoopIsCheap() throws {
        let probe = PapyrusWorldProbeDispatch()
        let alone = try Self.world(
            scripts: [("Waiter", Self.waitingLoop(note: "waiter"))], probe: probe
        )
        for _ in 0 ..< 60 {
            alone.stepFixed()
        }
        // One wake in 60 steps of 1/30 s, at step 31, with a few instructions.
        #expect(alone.runtime.tally.instructionsExecuted < 20)
        #expect(probe.notes == ["waiter"])

        let crowdProbe = PapyrusWorldProbeDispatch()
        let crowd = try Self.world(
            scripts: [
                ("Waiter", Self.waitingLoop(note: "waiter")),
                ("SpinA", Self.busyLoop(note: "a")),
                ("SpinB", Self.busyLoop(note: "b"))
            ],
            probe: crowdProbe
        )
        crowd.budget = PapyrusTickBudget(events: 32, instructions: 50)
        for _ in 0 ..< 60 {
            crowd.stepFixed()
        }
        #expect(crowdProbe.notes.filter { $0 == "waiter" }.count >= 1)
    }

    @Test("outside a step, nothing limits a call")
    func callsOutsideAStepAreNotLimited() throws {
        let world = try Self.world(
            scripts: [("Waiter", Self.waitingLoop(note: "waiter"))],
            probe: PapyrusWorldProbeDispatch()
        )
        world.budget = PapyrusTickBudget(events: 32, instructions: 1)
        world.stepFixed()
        #expect(world.runtime.stepInstructionsLeft == .max)
    }

    // MARK: Fixtures

    /// `Probe.Note(note)`, then jump back to it, forever.
    private static func busyLoop(note: String) -> PexFunction {
        PexFixture.runtimeFunction(instructions: [
            noteInstruction(note),
            PapyrusTestSupport.instruction(.jump, .integer(-1))
        ])
    }

    /// `Utility.Wait(1.0)`, `Probe.Note(note)`, then back to the wait, like `CritterSpawn`.
    private static func waitingLoop(note: String) -> PexFunction {
        PexFixture.runtimeFunction(instructions: [
            PapyrusTestSupport.instruction(
                .callStatic, .identifier("Utility"), .identifier("Wait"),
                .identifier("::nonevar"), .integer(1), .float(1)
            ),
            noteInstruction(note),
            PapyrusTestSupport.instruction(.jump, .integer(-2))
        ])
    }

    private static func noteInstruction(_ note: String) -> PexInstruction {
        PapyrusTestSupport.instruction(
            .callStatic, .identifier("Probe"), .identifier("Note"),
            .identifier("::nonevar"), .integer(1), .string(note)
        )
    }

    /// One reference per script, each with its `OnLoad` queued.
    private static func world(
        scripts: [(name: String, onLoad: PexFunction)],
        probe: PapyrusWorldProbeDispatch
    ) throws -> PapyrusWorldRuntime {
        let world = PapyrusWorldFixture.worldRuntime(
            objects: scripts.map {
                PapyrusWorldFixture.eventScript($0.name, events: [("OnLoad", $0.onLoad)])
            },
            nativeDispatch: probe
        )
        let entries = try scripts.enumerated().map { index, script in
            try PapyrusWorldFixture.referenceEntry(
                objectID: UInt32(index + 1), scripts: [.init(script.name, properties: [])]
            )
        }
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: PapyrusWorldFixture.index(entries),
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        world.eventQueue = scripts.enumerated().map { index, script in
            PapyrusScriptEvent(
                target: PapyrusWorldFixture.key(objectID: UInt32(index + 1), script: script.name),
                functionName: "OnLoad",
                arguments: []
            )
        }
        return world
    }
}
