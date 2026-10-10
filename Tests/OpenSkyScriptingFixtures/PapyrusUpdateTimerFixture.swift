// The update-timer script and session the timer, clock, persistence and save
// suites share.

@testable import OpenSkyFormatsPEX
import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

/// Shared fixture for the update-timer test suites: one scripted reference
/// whose `OnUpdate` and `OnUpdateGameTime` handlers each record a note, plus
/// native invocation through the session's standard registry.
@MainActor
public enum PapyrusUpdateTimerFixture {
    public static let refID: UInt32 = 0x601
    public static let scriptName = "TimerScript"

    public static var instanceKey: PapyrusInstanceKey {
        PapyrusWorldFixture.key(objectID: refID, script: scriptName)
    }

    public static func timerScript(_ name: String = scriptName) -> PexObject {
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
    public static func formScript() -> PexObject {
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

    public static func session(
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

    public static func handle(
        _ session: PapyrusWorldFixture.Session
    ) -> PapyrusObjectHandle {
        session.world.instancesByKey[instanceKey] ?? PapyrusObjectHandle(0)
    }

    /// Calls one `Form` native through the standard registry, the way the
    /// interpreter dispatches `self.RegisterForUpdate(...)`.
    public static func invoke(
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

    public static func updateNotes(
        _ session: PapyrusWorldFixture.Session
    ) -> [String] {
        session.dispatch.notes.filter { $0.hasSuffix(".onupdate") }
    }

    public static func gameTimeNotes(
        _ session: PapyrusWorldFixture.Session
    ) -> [String] {
        session.dispatch.notes.filter { $0.hasSuffix(".ongametime") }
    }

    public static func advanced(_ clock: GameClock, hours: Double) -> GameClock {
        GameClock(
            totalGameSeconds: clock.totalGameSeconds
                + hours * GameClock.secondsPerHour
        )
    }

    /// First fixed step at which a real-time delay of `interval` is due,
    /// using the registry's own whole-tick arithmetic.
    public static func dueStep(interval: Double, stepSeconds: Double) -> Int {
        var step = 1
        while Double(step) * stepSeconds < interval {
            step += 1
        }
        return step
    }
}
