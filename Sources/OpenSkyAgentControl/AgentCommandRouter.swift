// Turns one request into calls on `AgentControlWorld`. A command that must
// wait for frames (step, hold, events) returns a wait the host polls.

import Foundation

/// What a waiting command reports on one poll.
nonisolated public struct AgentWaitStep: Sendable {
    public var events: [AgentEvent]
    /// Set when the command is done; the host then sends the final reply.
    public var finish: Result<AgentJSON, AgentFailure>?

    public static let wait = Self(events: [], finish: nil)

    public static func done(_ result: Result<AgentJSON, AgentFailure>) -> Self {
        Self(events: [], finish: result)
    }
}

/// A command still running. `poll` gets the host clock in seconds.
public struct AgentWait {
    public let poll: @MainActor (Double) -> AgentWaitStep

    public init(poll: @escaping @MainActor (Double) -> AgentWaitStep) {
        self.poll = poll
    }
}

public enum AgentHandling {
    case done(Result<AgentJSON, AgentFailure>)
    case waiting(AgentWait)
}

@MainActor
public final class AgentCommandRouter {
    public weak var world: (any AgentControlWorld)?
    public private(set) var eventLog = AgentEventLog()
    /// Set by `quit`; the host quits once the reply is written.
    public private(set) var quitRequested = false

    /// True once per `quit` request, so the app terminates once.
    public func consumeQuitRequest() -> Bool {
        defer { quitRequested = false }
        return quitRequested
    }

    /// Seconds per stepped frame unless a step names its own.
    public static let defaultStepSeconds = 1.0 / 60

    public init() {}

    public var context: AgentReplyContext {
        let timeline = world?.agentTimeline
        return AgentReplyContext(
            frame: timeline?.frame ?? 0,
            paused: timeline?.paused ?? false,
            eventSeq: eventLog.lastSeq
        )
    }

    public func emit(_ kind: String, _ data: [String: AgentJSON] = [:]) {
        eventLog.append(kind: kind, frame: context.frame, data: data)
    }

    /// Lets the game diff its state into events. The host calls it every poll.
    public func pollWorldEvents() {
        world?.pollEvents { kind, data in emit(kind, data) }
    }

    public func handle(_ request: AgentRequest, now: Double) -> AgentHandling {
        let args = AgentArguments(command: request.command, values: request.args)
        if request.command == "status" {
            return .done(.success(status()))
        }
        guard let world else {
            return .done(.failure(AgentFailure(.notReady, "no game is running in the app")))
        }
        do {
            return try route(request.command, args: args, world: world, now: now)
        } catch {
            return .done(.failure(error))
        }
    }

    private func route(
        _ command: String,
        args: AgentArguments,
        world: any AgentControlWorld,
        now: Double
    ) throws(AgentFailure) -> AgentHandling {
        let parts = command.split(separator: ".", maxSplits: 1).map(String.init)
        let group = parts.first ?? ""
        let name = parts.count > 1 ? parts[1] : ""
        switch group {
        case "quit":
            quitRequested = true
            return .done(.success(["quitting": true]))
        case "screenshot":
            return try .done(.success(world.captureScreenshot(.parse(args))))
        case "time":
            return try routeTime(name, args: args, world: world)
        case "input":
            return try routeInput(name, args: args, world: world, now: now)
        case "state":
            return try .done(.success(world.query(.parse(name, args))))
        case "debug":
            return try world.perform(.parse(name, args))
        case "events":
            return try events(args, now: now)
        default:
            throw AgentFailure(.unknownCommand, "unknown command: \(command)")
        }
    }

    private func status() -> AgentJSON {
        let status = world?.agentStatus
        var fields: [String: AgentJSON] = [
            "protocolVersion": .init(AgentProtocol.version),
            "running": .bool(world != nil),
            "worldReady": .bool(status?.worldReady ?? false),
            "dataRoot": .init(status?.dataRoot),
            "mode": .init(status?.mode)
        ]
        if let timeline = world?.agentTimeline {
            fields["time"] = timeline.json
        }
        return .object(fields)
    }

    // MARK: - Time

    private func routeTime(
        _ name: String,
        args: AgentArguments,
        world: any AgentControlWorld
    ) throws(AgentFailure) -> AgentHandling {
        switch name {
        case "pause":
            if !world.agentTimeline.paused {
                world.pauseSimulation()
                emit(AgentEventKind.paused)
            }
            return .done(.success(world.agentTimeline.json))
        case "resume":
            if world.agentTimeline.paused {
                world.resumeSimulation()
                emit(AgentEventKind.resumed)
            }
            return .done(.success(world.agentTimeline.json))
        case "step":
            let count = try args.optionalInt("n") ?? 1
            guard (1 ... 100_000).contains(count) else { throw args.invalid("n", "1 to 100000") }
            let seconds = try Double(args
                .optionalFloat("seconds") ?? Float(Self.defaultStepSeconds))
            guard seconds > 0, seconds <= 0.1 else { throw args.invalid("seconds", "in (0, 0.1]") }
            return .waiting(step(count, seconds: seconds, world: world, then: nil))
        case "scale":
            try world.setTimeScale(Double(args.float("x")))
            return .done(.success(world.agentTimeline.json))
        default:
            throw AgentFailure(.unknownCommand, "unknown time command: \(name)")
        }
    }

    /// Pauses if needed, queues the steps, and finishes once all are drawn.
    private func step(
        _ count: Int,
        seconds: Double,
        world: any AgentControlWorld,
        then finish: (@MainActor () throws(AgentFailure) -> AgentJSON)?
    ) -> AgentWait {
        if !world.agentTimeline.paused {
            world.pauseSimulation()
            emit(AgentEventKind.paused)
        }
        world.requestSteps(count, seconds: seconds)
        return AgentWait { [weak world] _ in
            guard let world else {
                return .done(.failure(AgentFailure(.notReady, "the game closed")))
            }
            guard world.agentTimeline.pendingSteps == 0 else { return .wait }
            do throws(AgentFailure) {
                return try .done(.success(finish?() ?? world.agentTimeline.json))
            } catch {
                return .done(.failure(error))
            }
        }
    }

    // MARK: - Input

    private func routeInput(
        _ name: String,
        args: AgentArguments,
        world: any AgentControlWorld,
        now: Double
    ) throws(AgentFailure) -> AgentHandling {
        switch name {
        case "press", "release":
            let action = try args.string("action")
            let phase: AgentInputPhase = name == "press" ? .press : .release
            let held = try world.applyInput(action, phase: phase)
            return .done(.success([
                "action": .string(action),
                "held": .bool(held && phase == .press)
            ]))
        case "hold":
            return try hold(args, world: world, now: now)
        case "look":
            let yaw = try args.optionalFloat("dx") ?? 0
            let pitch = try args.optionalFloat("dy") ?? 0
            try world.look(yawDegrees: yaw, pitchDegrees: pitch)
            return .done(.success(["dx": .init(yaw), "dy": .init(pitch)]))
        case "select":
            return try .done(.success(world.selectMenuRow(label: args.string("label"))))
        default:
            throw AgentFailure(.unknownCommand, "unknown input command: \(name)")
        }
    }

    /// Holds an action for a number of frames or seconds, then releases it.
    /// Paused, the frames are stepped; running, they are counted as they draw.
    private func hold(
        _ args: AgentArguments,
        world: any AgentControlWorld,
        now: Double
    ) throws(AgentFailure) -> AgentHandling {
        let action = try args.string("action")
        let frames = try args.optionalInt("frames")
        let seconds = try args.optionalFloat("seconds")
        guard (frames == nil) != (seconds == nil) else {
            throw AgentFailure(.invalidArgument, "input.hold: give frames or seconds, not both")
        }
        if let frames, !(1 ... 100_000).contains(frames) {
            throw args.invalid("frames", "1 to 100000")
        }
        if let seconds, !(seconds > 0 && seconds <= 600) {
            throw args.invalid("seconds", "in (0, 600]")
        }
        guard try world.applyInput(action, phase: .press) else {
            throw AgentFailure(.invalidArgument, "input.hold: \(action) is not a held action")
        }
        let release: @MainActor () throws(AgentFailure)
            -> AgentJSON = { [weak world] () throws(AgentFailure) in
                _ = try world?.applyInput(action, phase: .release)
                return ["action": .string(action), "released": true]
            }
        if let frames, world.agentTimeline.paused {
            return .waiting(step(
                frames,
                seconds: Self.defaultStepSeconds,
                world: world,
                then: release
            ))
        }
        let startFrame = world.agentTimeline.frame
        return .waiting(AgentWait { [weak world] clock in
            let elapsed = if let frames {
                (world?.agentTimeline.frame ?? .max) - startFrame >= frames
            } else {
                clock - now >= Double(seconds ?? 0)
            }
            guard elapsed else { return .wait }
            do throws(AgentFailure) {
                return try .done(.success(release()))
            } catch {
                return .done(.failure(error))
            }
        })
    }
}
