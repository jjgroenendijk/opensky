// Update-timer registry and the `Form` natives (issue #277): single-shot and
// repeating cadence at the fixed step, slot replacement and coexistence,
// interval clamping, same-step registration order, and bytecode dispatch
// through a script chain that declares the natives on `Form`.
//
// Synthetic PEX objects and synthetic REFR records only. Real-time cadence is
// asserted in the scheduler's own arithmetic — the first step `n` where
// `Double(n) * fixedStepSeconds >= interval` — so the expectations share the
// exact rounding the registry uses.

@testable import opensky
import Testing

/// Shared fixture for the update-timer test suites: one scripted reference
/// whose `OnUpdate` and `OnUpdateGameTime` handlers each record a note, plus
/// native invocation through the session's standard registry.
@MainActor
enum PapyrusUpdateTimerFixture {
    static let refID: UInt32 = 0x601
    static let scriptName = "TimerScript"

    static var instanceKey: PapyrusInstanceKey {
        PapyrusWorldFixture.key(objectID: refID, script: scriptName)
    }

    static func timerScript(_ name: String = scriptName) -> PexObject {
        let key = PapyrusRuntime.key(name)
        return PapyrusWorldFixture.eventScript(name, events: [
            ("OnUpdate", PapyrusWorldFixture.probeBody(note: "\(key).onupdate")),
            (
                "OnUpdateGameTime",
                PapyrusWorldFixture.probeBody(note: "\(key).ongametime")
            )
        ])
    }

    /// The base script the six natives are declared on, the same shape the
    /// game's own `Form.pex` has: native-flagged functions with no body.
    static func formScript() -> PexObject {
        let names = [
            "RegisterForUpdate", "RegisterForSingleUpdate",
            "RegisterForUpdateGameTime", "RegisterForSingleUpdateGameTime",
            "UnregisterForUpdate", "UnregisterForUpdateGameTime"
        ]
        return PexFixture.runtimeObject(
            name: "Form",
            states: [PapyrusTestSupport.state(functions: names.map {
                ($0, PexFixture.runtimeFunction(flags: .native, instructions: []))
            })]
        )
    }

    static func session(
        isPersistent: Bool = false
    ) throws -> PapyrusWorldFixture.Session {
        let entry = try PapyrusWorldFixture.referenceEntry(
            objectID: refID,
            scripts: [VMADFixture.Script(scriptName, properties: [])],
            isPersistent: isPersistent
        )
        let session = PapyrusWorldFixture.session(
            objects: [timerScript()], entries: [entry]
        )
        PapyrusWorldFixture.drain(session.world)
        return session
    }

    static func handle(
        _ session: PapyrusWorldFixture.Session
    ) -> PapyrusObjectHandle {
        session.world.instancesByKey[instanceKey] ?? PapyrusObjectHandle(0)
    }

    /// Calls one `Form` native through the standard registry, the way the
    /// interpreter dispatches `self.RegisterForUpdate(...)`.
    static func invoke(
        _ session: PapyrusWorldFixture.Session,
        _ functionName: String,
        interval: Float? = nil,
        receiver: PapyrusObjectHandle? = nil
    ) {
        let result = PapyrusWorldFixture.registry(for: session).invoke(
            PapyrusWorldFixture.methodCall(
                "Form",
                functionName,
                receiver: receiver ?? handle(session),
                arguments: interval.map { [PapyrusValue.float($0)] } ?? []
            )
        )
        if case .returned = result {} else {
            Issue.record("\(functionName) failed: \(result)")
        }
    }

    static func updateNotes(
        _ session: PapyrusWorldFixture.Session
    ) -> [String] {
        session.dispatch.notes.filter { $0.hasSuffix(".onupdate") }
    }

    static func gameTimeNotes(
        _ session: PapyrusWorldFixture.Session
    ) -> [String] {
        session.dispatch.notes.filter { $0.hasSuffix(".ongametime") }
    }

    static func advanced(_ clock: GameClock, hours: Double) -> GameClock {
        GameClock(
            totalGameSeconds: clock.totalGameSeconds
                + hours * GameClock.secondsPerHour
        )
    }

    /// First fixed step at which a real-time delay of `interval` is due,
    /// using the registry's own whole-tick arithmetic.
    static func dueStep(interval: Double, stepSeconds: Double) -> Int {
        var step = 1
        while Double(step) * stepSeconds < interval {
            step += 1
        }
        return step
    }
}

@MainActor
struct PapyrusWorldUpdateTimerTests {
    private let step = 1.0 / 30.0

    @Test func singleShotFiresOnceAtTheDueStepAndNeverAgain() throws {
        let session = try PapyrusUpdateTimerFixture.session()
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForSingleUpdate", interval: 0.1
        )
        let due = PapyrusUpdateTimerFixture.dueStep(
            interval: Double(Float(0.1)), stepSeconds: step
        )
        for stepIndex in 1 ... due {
            _ = session.world.stepFixed()
            let expected = stepIndex == due ? 1 : 0
            #expect(
                PapyrusUpdateTimerFixture.updateNotes(session).count == expected
            )
        }
        for _ in 0 ..< 30 {
            _ = session.world.stepFixed()
        }
        #expect(PapyrusUpdateTimerFixture.updateNotes(session).count == 1)
        #expect(session.world.updateTimers.pendingCount == 0)
    }

    @Test func repeatingFiresAtItsCadenceOverManySteps() throws {
        let session = try PapyrusUpdateTimerFixture.session()
        // Float(0.05) is due on step 2 at a 1/30 step, so the cadence is one
        // fire every two steps.
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForUpdate", interval: 0.05
        )
        for stepIndex in 1 ... 10 {
            _ = session.world.stepFixed()
            #expect(
                PapyrusUpdateTimerFixture.updateNotes(session).count
                    == stepIndex / 2
            )
        }
        // The slot stays armed: repeating never clears itself.
        #expect(session.world.updateTimers.pendingCount == 1)
    }

    @Test func reRegisteringReplacesTheSlotAndSlotsCoexist() throws {
        let session = try PapyrusUpdateTimerFixture.session()
        // The 100-second single-shot is replaced by the 0.05-second one, so
        // only the second interval fires; the repeating slot is independent.
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForSingleUpdate", interval: 100
        )
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForSingleUpdate", interval: 0.05
        )
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForUpdate", interval: 0.1
        )
        #expect(session.world.updateTimers.pendingCount == 2)
        let repeatingDue = PapyrusUpdateTimerFixture.dueStep(
            interval: Double(Float(0.1)), stepSeconds: step
        )
        var expected = 0
        for stepIndex in 1 ... 3 * repeatingDue {
            _ = session.world.stepFixed()
            if stepIndex == 2 {
                expected += 1 // the replaced single-shot, at 0.05 s not 100 s
            }
            if stepIndex.isMultiple(of: repeatingDue) {
                expected += 1 // the repeating slot, every `repeatingDue` steps
            }
            #expect(
                PapyrusUpdateTimerFixture.updateNotes(session).count == expected
            )
        }
    }

    @Test func nonPositiveAndNonFiniteIntervalsClampToTheNextStep() throws {
        let session = try PapyrusUpdateTimerFixture.session()
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForSingleUpdate", interval: -5
        )
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForUpdate", interval: 0
        )
        _ = session.world.stepFixed()
        // Both clamp to zero and fire on the very next step.
        #expect(PapyrusUpdateTimerFixture.updateNotes(session).count == 2)
        for stepIndex in 1 ... 3 {
            _ = session.world.stepFixed()
            // The zero-interval repeating timer fires once per step, never
            // more — no infinite loop inside one step.
            #expect(
                PapyrusUpdateTimerFixture.updateNotes(session).count
                    == 2 + stepIndex
            )
        }
        PapyrusUpdateTimerFixture.invoke(session, "UnregisterForUpdate")
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForSingleUpdate", interval: Float.nan
        )
        _ = session.world.stepFixed()
        #expect(PapyrusUpdateTimerFixture.updateNotes(session).count == 6)
        _ = session.world.stepFixed()
        #expect(PapyrusUpdateTimerFixture.updateNotes(session).count == 6)
    }

    @Test func sameStepFiringsEnqueueInRegistrationOrder() throws {
        let entry = try PapyrusWorldFixture.referenceEntry(
            objectID: PapyrusUpdateTimerFixture.refID,
            scripts: [
                VMADFixture.Script("AScript", properties: []),
                VMADFixture.Script("BScript", properties: [])
            ]
        )
        let session = PapyrusWorldFixture.session(
            objects: [
                PapyrusUpdateTimerFixture.timerScript("AScript"),
                PapyrusUpdateTimerFixture.timerScript("BScript")
            ],
            entries: [entry]
        )
        PapyrusWorldFixture.drain(session.world)
        let aKey = PapyrusWorldFixture.key(
            objectID: PapyrusUpdateTimerFixture.refID, script: "AScript"
        )
        let bKey = PapyrusWorldFixture.key(
            objectID: PapyrusUpdateTimerFixture.refID, script: "BScript"
        )
        guard
            let aHandle = session.world.instancesByKey[aKey],
            let bHandle = session.world.instancesByKey[bKey]
        else {
            Issue.record("Fixture instances missing")
            return
        }
        // B registers first, so B fires first even though A's instance key
        // sorts lower.
        session.world.registerUpdateTimer(
            handle: bHandle, slot: .realSingleShot, interval: 0
        )
        session.world.registerUpdateTimer(
            handle: aHandle, slot: .realSingleShot, interval: 0
        )
        _ = session.world.stepFixed()
        #expect(PapyrusUpdateTimerFixture.updateNotes(session) == [
            "bscript.onupdate", "ascript.onupdate"
        ])
    }

    @Test func aScriptExtendingFormReachesTheNativesThroughItsChain() throws {
        // `SelfTimer extends Form`; its `OnInit` is the single instruction a
        // compiler emits for `Self.RegisterForSingleUpdate(0.0)`. Resolution
        // walks the chain to Form's native declaration and dispatches under
        // scriptName "Form", where the natives are registered.
        let onInit = PexFixture.runtimeFunction(instructions: [
            PapyrusTestSupport.instruction(
                .callMethod,
                .identifier("RegisterForSingleUpdate"),
                .identifier("self"),
                .identifier("::nonevar"),
                .integer(1),
                .float(0)
            )
        ])
        let script = PexFixture.runtimeObject(
            name: "SelfTimer",
            parent: "Form",
            states: [PapyrusTestSupport.state(functions: [
                ("OnInit", onInit),
                (
                    "OnUpdate",
                    PapyrusWorldFixture.probeBody(note: "selftimer.onupdate")
                )
            ])]
        )
        let entry = try PapyrusWorldFixture.referenceEntry(
            objectID: 0x611,
            scripts: [VMADFixture.Script("SelfTimer", properties: [])]
        )
        let session = PapyrusWorldFixture.session(
            objects: [PapyrusUpdateTimerFixture.formScript(), script],
            entries: [entry]
        )
        // The drain dispatches OnInit (which registers the timer), then the
        // next step fires OnUpdate; both settle before the queue is quiet.
        PapyrusWorldFixture.drain(session.world)
        #expect(session.dispatch.notes == ["selftimer.onupdate"])
        #expect(session.world.updateTimers.pendingCount == 0)
    }
}
