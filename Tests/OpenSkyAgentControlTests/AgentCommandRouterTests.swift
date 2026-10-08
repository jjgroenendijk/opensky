// The router against a fake game: immediate commands, frame waits, and events.

import Foundation
import OpenSkyAgentControl
import Testing

@MainActor
struct AgentCommandRouterTests {
    private let world = FakeAgentWorld()
    private let router = AgentCommandRouter()

    init() {
        router.world = world
    }

    private func run(_ command: String, _ args: [String: AgentJSON] = [:], now: Double = 0)
        -> AgentHandling
    {
        router.handle(AgentRequest(command: command, args: args), now: now)
    }

    private func result(_ handling: AgentHandling) -> Result<AgentJSON, AgentFailure>? {
        if case let .done(result) = handling {
            return result
        }
        return nil
    }

    private func failureCode(_ handling: AgentHandling) -> AgentErrorCode? {
        if case let .failure(failure)? = result(handling) {
            return failure.code
        }
        return nil
    }

    /// Polls a wait, drawing one fake frame between polls, until it finishes.
    private func finish(_ handling: AgentHandling, maxFrames: Int = 1000) -> AgentWaitStep? {
        guard case let .waiting(wait) = handling else { return nil }
        for frame in 0 ..< maxFrames {
            let step = wait.poll(Double(frame))
            if step.finish != nil {
                return step
            }
            world.drawFrame()
        }
        return nil
    }

    @Test func statusAnswersWithoutAGame() throws {
        router.world = nil
        let status = try #require(try result(run("status"))?.get())
        #expect(status["running"] == false)
        #expect(status["protocolVersion"]?.intValue == AgentProtocol.version)
        #expect(failureCode(run("state.player")) == .notReady)
    }

    @Test func unknownCommandsAndArgumentsAreTypedFailures() {
        #expect(failureCode(run("dance")) == .unknownCommand)
        #expect(failureCode(run("state.nothing")) == .unknownCommand)
        #expect(failureCode(run("input.press", ["action": "fly away"])) == .invalidArgument)
        #expect(failureCode(run("time.step", ["n": 0])) == .invalidArgument)
        #expect(failureCode(run("events", ["until": "explosion"])) == .invalidArgument)
    }

    @Test func steppingPausesFirstAndFinishesWhenTheFramesAreDrawn() throws {
        let step = try #require(finish(run("time.step", ["n": 5])))
        let timeline = try #require(try step.finish?.get())
        #expect(world.agentTimeline.paused)
        #expect(world.stepRequests == [5])
        #expect(timeline["pendingSteps"]?.intValue == 0)
        #expect(router.eventLog.events.map(\.kind) == [AgentEventKind.paused])
    }

    @Test func holdWhilePausedStepsThenReleases() throws {
        world.agentTimeline.paused = true
        let step = try #require(finish(run("input.hold", ["action": "forward", "frames": 60])))
        #expect(try step.finish?.get()["released"] == true)
        #expect(world.stepRequests == [60])
        #expect(world.inputLog == ["press forward", "release forward"])
    }

    @Test func textTypesIntoTheOpenMenu() throws {
        let request = try AgentCommandLine.request(["input", "text", "Brynja"])
        #expect(request.command == "input.text")
        let typed = try #require(result(run(request.command, request.args)))
        #expect(try typed.get()["typed"] == "Brynja")
        #expect(world.inputLog == ["text Brynja"])
    }

    @Test func clickTakesAPointAsFractionsOfTheView() throws {
        let request = try AgentCommandLine.request(["input", "click", "--x", "0.5", "--y", "0.25"])
        #expect(request.command == "input.click")
        let clicked = try #require(result(run(request.command, request.args)))
        #expect(try clicked.get()["clicked"] == true)
        #expect(world.inputLog == ["click 0.5 0.25"])
        #expect(failureCode(run("input.point", ["x": 1.5, "y": 0])) == .invalidArgument)
    }

    @Test func holdWhileRunningCountsDrawnFrames() throws {
        let start = world.agentTimeline.frame
        _ = try #require(finish(run("input.hold", ["action": "back", "frames": 3])))
        #expect(world.agentTimeline.frame - start == 3)
        #expect(world.stepRequests.isEmpty)
    }

    @Test func holdRefusesAOneShotAction() {
        #expect(failureCode(run("input.hold", ["action": "jump", "frames": 2])) == .invalidArgument)
    }

    @Test func eventsUntilReturnsTheFirstMatchAfterTheRequest() throws {
        router.emit(AgentEventKind.menuOpened, ["menu": "Old"])
        let handling = run("events", ["until": "menu.opened", "timeout": 5])
        guard case let .waiting(wait) = handling else {
            Issue.record("expected a wait")
            return
        }
        #expect(wait.poll(0).finish == nil)
        router.emit(AgentEventKind.activation)
        router.emit(AgentEventKind.menuOpened, ["menu": "InventoryMenu"])
        let found = try #require(try wait.poll(1).finish?.get())
        #expect(found.value(atPath: "event.data.menu") == "InventoryMenu")
    }

    @Test func eventsUntilTimesOut() {
        guard
            case let .waiting(wait) = run(
                "events",
                ["until": "actor.death", "timeout": 2],
                now: 10
            )
        else {
            Issue.record("expected a wait")
            return
        }
        #expect(wait.poll(11).finish == nil)
        if case let .failure(failure)? = wait.poll(12).finish {
            #expect(failure.code == .timeout)
        } else {
            Issue.record("expected a timeout")
        }
    }

    @Test func followStreamsOnlyFilteredKinds() {
        guard
            case let .waiting(wait) = run(
                "events",
                ["follow": true, "filter": "cell.loaded", "timeout": 1]
            )
        else {
            Issue.record("expected a wait")
            return
        }
        world.pendingEvents = [("cell.loaded", ["cell": "A"]), ("activation", [:])]
        router.pollWorldEvents()
        let step = wait.poll(0.5)
        #expect(step.events.map(\.kind) == ["cell.loaded"])
        #expect(step.finish == nil)
        #expect(wait.poll(1.5).finish != nil)
    }

    @Test func aPlainListingReturnsTheRing() throws {
        router.emit(AgentEventKind.cellLoaded)
        router.emit(AgentEventKind.log, ["text": "[WARNING] x"])
        let listed = try #require(try result(run("events", ["filter": ["log"]]))?.get())
        #expect(listed["events"]?.arrayValue?.count == 1)
    }

    @Test func quitIsRequestedNotPerformedByTheRouter() {
        _ = run("quit")
        #expect(router.quitRequested)
        #expect(world.quitCount == 0)
        #expect(router.consumeQuitRequest())
        #expect(!router.consumeQuitRequest())
    }
}

@MainActor
struct AgentControlProvidingTests {
    private let world = FakeAgentWorld()
    private let coordinator = AgentControlCoordinator(socketPath: "/tmp/opensky-agent-unused.sock")

    init() {
        coordinator.attach(world: world)
    }

    @Test func thePauseControlFreezesAndResumesTheWorld() {
        coordinator.isAgentSimulationPaused = true
        #expect(world.agentTimeline.paused)
        #expect(coordinator.agentControlSnapshot.timeline?.paused == true)
        coordinator.isAgentSimulationPaused = false
        #expect(!world.agentTimeline.paused)
    }

    @Test func aStepPausesThenQueuesFrames() {
        coordinator.stepAgentSimulation(frames: 1)
        #expect(world.agentTimeline.paused)
        #expect(world.stepRequests == [1])
    }

    @Test func theSnapshotShowsAnOffServer() {
        let snapshot = coordinator.agentControlSnapshot
        #expect(!snapshot.enabled)
        #expect(snapshot.connections == 0)
        #expect(snapshot.socketPath == "/tmp/opensky-agent-unused.sock")
    }
}
