// Fixed-step wake policy for real-time and game-time latent calls.

import Foundation
@testable import opensky
import Testing

struct PapyrusSchedulerTests {
    @Test func realTimeWaitResumesTheSavedFrameAtTheFixedStep() {
        let (runtime, handle) = waitRuntime(
            scriptName: "RealWait",
            utilityFunction: "Wait",
            duration: 0.5,
            returnValue: 17
        )
        let scheduler = PapyrusScheduler(runtime: runtime, fixedStepSeconds: 0.25)
        scheduler.schedule(runtime.invoke("Run", on: handle))
        #expect(scheduler.pendingCount == 1)
        #expect(scheduler.tick().isEmpty)
        let outcomes = scheduler.tick()
        #expect(outcomes.count == 1)
        #expect(PapyrusTestSupport.value(outcomes[0]) == .integer(17))
        #expect(scheduler.pendingCount == 0)
    }

    @Test func sameTickWakesKeepRegistrationOrder() {
        let first = waitObject("FirstWait", returnValue: 1)
        let second = waitObject("SecondWait", returnValue: 2)
        let runtime = PapyrusRuntime(
            files: [PexFixture.runtimeFile(objects: [first, second])]
        )
        let firstHandle = try? runtime.makeInstance(scriptName: first.name)
        let secondHandle = try? runtime.makeInstance(scriptName: second.name)
        let scheduler = PapyrusScheduler(runtime: runtime, fixedStepSeconds: 1)
        if let firstHandle, let secondHandle {
            scheduler.schedule(runtime.invoke("Run", on: firstHandle))
            scheduler.schedule(runtime.invoke("Run", on: secondHandle))
        } else {
            Issue.record("Could not create wait instances")
        }

        let values = scheduler.tick().compactMap(PapyrusTestSupport.value)
        #expect(values == [.integer(1), .integer(2)])
    }

    @Test func gameTimeIgnoresBackwardsJumpsAndCapsOneForwardStep() {
        let (runtime, handle) = waitRuntime(
            scriptName: "GameWait",
            utilityFunction: "WaitGameTime",
            duration: 30,
            returnValue: 9
        )
        let scheduler = PapyrusScheduler(
            runtime: runtime,
            fixedStepSeconds: 0,
            maximumGameHoursPerStep: 24
        )
        var clock = GameClock(hour: 12)
        _ = scheduler.tick(gameClock: clock)
        scheduler.schedule(runtime.invoke("Run", on: handle))

        clock.setHour(6)
        #expect(scheduler.tick(gameClock: clock).isEmpty)
        #expect(scheduler.elapsedGameHours == 0)

        clock = GameClock(
            totalGameSeconds: clock.totalGameSeconds + 100 * GameClock.secondsPerHour
        )
        #expect(scheduler.tick(gameClock: clock).isEmpty)
        #expect(scheduler.elapsedGameHours == 24)

        clock = GameClock(
            totalGameSeconds: clock.totalGameSeconds + 6 * GameClock.secondsPerHour
        )
        let outcomes = scheduler.tick(gameClock: clock)
        #expect(PapyrusTestSupport.value(outcomes.first ?? .completed(.none)) == .integer(9))
        #expect(scheduler.elapsedGameHours == 30)
    }

    private func waitRuntime(
        scriptName: String,
        utilityFunction: String,
        duration: Float,
        returnValue: Int32
    ) -> (PapyrusRuntime, PapyrusObjectHandle) {
        let script = waitObject(
            scriptName,
            utilityFunction: utilityFunction,
            duration: duration,
            returnValue: returnValue
        )
        return PapyrusTestSupport.runtime(
            objects: [script],
            nativeDispatch: PapyrusNativeRegistry.standard
        )
    }

    private func waitObject(
        _ name: String,
        utilityFunction: String = "Wait",
        duration: Float = 1,
        returnValue: Int32
    ) -> PexObject {
        let run = PexFixture.runtimeFunction(
            returnType: "Int",
            instructions: [
                PapyrusTestSupport.instruction(
                    .callStatic,
                    .identifier("Utility"),
                    .identifier(utilityFunction),
                    .identifier("::nonevar"),
                    .integer(1),
                    .float(duration)
                ),
                PapyrusTestSupport.instruction(.returnValue, .integer(returnValue))
            ]
        )
        return PexFixture.runtimeObject(
            name: name,
            states: [PapyrusTestSupport.state(functions: [("Run", run)])]
        )
    }
}
