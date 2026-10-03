// Owns the control server and the router, and is polled by the app on the
// main actor. Each connection runs one request at a time, in order.

import Foundation

/// What the sidebar shows about the server.
nonisolated public struct AgentControlSnapshot: Equatable, Sendable {
    public var enabled: Bool
    public var socketPath: String
    public var connections: Int
    public var lastError: String?
    public var recentCommands: [String]
    public var timeline: AgentTimeline?

    public init(
        enabled: Bool,
        socketPath: String,
        connections: Int,
        lastError: String?,
        recentCommands: [String],
        timeline: AgentTimeline?
    ) {
        self.enabled = enabled
        self.socketPath = socketPath
        self.connections = connections
        self.lastError = lastError
        self.recentCommands = recentCommands
        self.timeline = timeline
    }

    /// What a game view without a host shows.
    public static let unavailable = AgentControlSnapshot(
        enabled: false, socketPath: "", connections: 0, lastError: "no agent control host",
        recentCommands: [], timeline: nil
    )
}

/// The sidebar seam over the coordinator.
@MainActor
public protocol AgentControlProviding: AnyObject {
    var agentControlSnapshot: AgentControlSnapshot { get }
    var isAgentControlEnabled: Bool { get set }
    var isAgentSimulationPaused: Bool { get set }
    func stepAgentSimulation(frames: Int)
}

@MainActor
public final class AgentControlCoordinator {
    private struct Connection {
        var queue: [AgentSocketEvent] = []
        var active: (id: Int, wait: AgentWait)?
    }

    public static let recentCommandLimit = 12

    public let router = AgentCommandRouter()
    public let socketPath: String
    public private(set) var lastError: String?
    public private(set) var recentCommands: [String] = []
    /// The app's version string for the hello line.
    public var appVersion = "dev"
    /// Host seconds, injectable so a test can move time.
    public var now: () -> Double = { ProcessInfo.processInfo.systemUptime }
    /// Called after the server starts or stops, so the host can start or stop polling.
    public var onEnabledChange: ((Bool) -> Void)?

    private var server: AgentSocketServer?
    private var connections: [Int: Connection] = [:]

    public init(socketPath: String = AgentSocketLocation.path()) {
        self.socketPath = socketPath
    }

    public var isEnabled: Bool {
        server != nil
    }

    public var connectionCount: Int {
        server?.connectionCount ?? 0
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        defer { onEnabledChange?(isEnabled) }
        guard enabled else {
            server?.stop()
            server = nil
            connections.removeAll()
            return
        }
        let candidate = AgentSocketServer(path: socketPath)
        do {
            try candidate.start()
            server = candidate
            lastError = nil
        } catch {
            lastError = error.message
        }
    }

    public func attach(world: any AgentControlWorld) {
        router.world = world
    }

    public var snapshot: AgentControlSnapshot {
        AgentControlSnapshot(
            enabled: isEnabled,
            socketPath: socketPath,
            connections: connectionCount,
            lastError: lastError,
            recentCommands: recentCommands,
            timeline: router.world?.agentTimeline
        )
    }

    /// One pass: accept, read, run queued requests, advance waits, write.
    public func poll() {
        guard let server else { return }
        router.pollWorldEvents()
        for event in server.poll() {
            receive(event, server: server)
        }
        for id in connections.keys.sorted() {
            advance(id, server: server)
        }
        if router.consumeQuitRequest() {
            router.world?.quitApplication()
        }
    }

    private func receive(_ event: AgentSocketEvent, server: AgentSocketServer) {
        switch event {
        case let .connected(id):
            connections[id] = Connection()
            server.send(AgentLineCodec.encode(hello()), to: id)
        case let .disconnected(id):
            connections[id] = nil
        case let .line(id, _), let .lineTooLong(id):
            connections[id]?.queue.append(event)
        }
    }

    private func hello() -> AgentHello {
        let status = router.world?.agentStatus
        return AgentHello(
            appVersion: appVersion,
            dataRoot: status?.dataRoot,
            worldReady: status?.worldReady ?? false
        )
    }

    private func advance(_ id: Int, server: AgentSocketServer) {
        guard var connection = connections[id] else { return }
        if let (requestID, wait) = connection.active {
            let step = wait.poll(now())
            for event in step.events {
                server.send(
                    AgentLineCodec.encode(AgentStreamLine(id: requestID, event: event)),
                    to: id
                )
            }
            guard let finish = step.finish else { return }
            reply(requestID, finish, to: id, server: server)
            connection.active = nil
        }
        while connection.active == nil, !connection.queue.isEmpty {
            let event = connection.queue.removeFirst()
            connection.active = start(event, connection: id, server: server)
        }
        connections[id] = connection
    }

    /// Runs one request. Returns the wait when it did not finish at once.
    private func start(
        _ event: AgentSocketEvent,
        connection: Int,
        server: AgentSocketServer
    ) -> (id: Int, wait: AgentWait)? {
        guard case let .line(_, data) = event else {
            let failure = AgentFailure(.malformedRequest, "request line over the size cap")
            reply(0, .failure(failure), to: connection, server: server)
            return nil
        }
        let request: AgentRequest
        do {
            request = try AgentLineCodec.decodeRequest(data)
        } catch {
            reply(0, .failure(error), to: connection, server: server)
            return nil
        }
        record(request.command)
        switch router.handle(request, now: now()) {
        case let .done(result):
            reply(request.id, result, to: connection, server: server)
            return nil
        case let .waiting(wait):
            return (request.id, wait)
        }
    }

    private func reply(
        _ requestID: Int,
        _ result: Result<AgentJSON, AgentFailure>,
        to connection: Int,
        server: AgentSocketServer
    ) {
        let reply = switch result {
        case let .success(value): AgentReply(id: requestID, context: router.context, result: value)
        case let .failure(failure): AgentReply(
                id: requestID,
                context: router.context,
                error: failure
            )
        }
        if case let .failure(failure) = result {
            record("  -> \(failure.code.rawValue)")
        }
        server.send(AgentLineCodec.encode(reply), to: connection)
    }

    private func record(_ line: String) {
        recentCommands.append("\(router.context.frame) \(line)")
        if recentCommands.count > Self.recentCommandLimit {
            recentCommands.removeFirst(recentCommands.count - Self.recentCommandLimit)
        }
    }
}

extension AgentControlCoordinator: AgentControlProviding {
    public var agentControlSnapshot: AgentControlSnapshot {
        snapshot
    }

    public var isAgentControlEnabled: Bool {
        get { isEnabled }
        set { setEnabled(newValue) }
    }

    public var isAgentSimulationPaused: Bool {
        get { router.world?.agentTimeline.paused ?? false }
        set {
            if newValue {
                router.world?.pauseSimulation()
            } else {
                router.world?.resumeSimulation()
            }
        }
    }

    public func stepAgentSimulation(frames: Int) {
        guard let world = router.world, frames > 0 else { return }
        world.pauseSimulation()
        world.requestSteps(frames, seconds: AgentCommandRouter.defaultStepSeconds)
    }
}

/// Lets a host conform to `AgentControlProviding` in one line.
@MainActor
public protocol AgentControlForwarding: AgentControlProviding {
    var agentControl: AgentControlCoordinator? { get }
}

extension AgentControlForwarding {
    public var agentControlSnapshot: AgentControlSnapshot {
        agentControl?.snapshot ?? .unavailable
    }

    public var isAgentControlEnabled: Bool {
        get { agentControl?.isAgentControlEnabled ?? false }
        set { agentControl?.isAgentControlEnabled = newValue }
    }

    public var isAgentSimulationPaused: Bool {
        get { agentControl?.isAgentSimulationPaused ?? false }
        set { agentControl?.isAgentSimulationPaused = newValue }
    }

    public func stepAgentSimulation(frames: Int) {
        agentControl?.stepAgentSimulation(frames: frames)
    }
}
