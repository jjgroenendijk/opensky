// The real socket: the coordinator polls on the main actor while a client
// blocks beside it, as `openskycli game` does against the app.

import Darwin
import Foundation
import OpenSkyAgentControl
import Synchronization
import Testing

@MainActor
@Suite(.serialized)
struct AgentSocketTests {
    private let path: String

    init() {
        // sun_path is short, so the temporary folder is used directly.
        path = "/tmp/opensky-agent-\(UUID().uuidString.prefix(8)).sock"
    }

    /// Runs `client` off the main actor and polls `coordinator` until it returns.
    /// The fake draws one frame per poll, as the app's display does.
    private func drive<Value: Sendable>(
        _ coordinator: AgentControlCoordinator,
        world: FakeAgentWorld? = nil,
        client: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let outcome = Mutex<Result<Value, any Error>?>(nil)
        let task = Task { @concurrent in
            let result = Result { try client() }
            outcome.withLock { $0 = result }
        }
        for _ in 0 ..< 2000 {
            coordinator.poll()
            world?.drawFrame()
            if let result = outcome.withLock({ $0 }) {
                await task.value
                return try result.get()
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw AgentFailure(.timeout, "client did not finish")
    }

    nonisolated private static func roundTrip(
        _ path: String,
        _ requests: [AgentRequest]
    ) throws -> [AgentReply] {
        let client = AgentSocketClient(path: path)
        _ = try client.connect(timeout: 5)
        return try requests.map { request in
            try client.send(request)
            return try AgentLineCodec.decode(AgentReply.self, from: client.readLine(timeout: 5))
        }
    }

    @Test func withTheServerOffTheClientReportsNotRunning() {
        let client = AgentSocketClient(path: path)
        #expect(throws: AgentFailure.self) { try client.connect(timeout: 1) }
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func aRequestRoundTripsAndTheSocketIsPrivate() async throws {
        let coordinator = AgentControlCoordinator(socketPath: path)
        let world = FakeAgentWorld()
        coordinator.attach(world: world)
        coordinator.setEnabled(true)
        defer { coordinator.setEnabled(false) }

        var info = stat()
        #expect(stat(path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o600)

        let path = path
        let replies = try await drive(coordinator, world: world) {
            try Self.roundTrip(path, [
                AgentRequest(id: 1, command: "state.player"),
                AgentRequest(id: 2, command: "time.step", args: ["n": 2])
            ])
        }
        #expect(replies.map(\.id) == [1, 2])
        #expect(replies[0].result?.value(atPath: "position.2") == 3)
        #expect(replies[1].paused)
        #expect(coordinator.recentCommands.count == 2)
        coordinator.setEnabled(false)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func aMalformedLineGetsAnErrorReplyAndTheConnectionLives() async throws {
        let coordinator = AgentControlCoordinator(socketPath: path)
        coordinator.attach(world: FakeAgentWorld())
        coordinator.setEnabled(true)
        defer { coordinator.setEnabled(false) }

        let path = path
        let replies = try await drive(coordinator) { () throws -> [AgentReply] in
            let socket = try RawSocket(path: path)
            _ = try socket.readLine()
            try socket.write("garbage\n{\"id\":5,\"command\":\"status\"}\n")
            return try [socket.readLine(), socket.readLine()].map {
                try AgentLineCodec.decode(AgentReply.self, from: $0)
            }
        }
        #expect(replies[0].error?.code == .malformedRequest)
        #expect(replies[1].id == 5)
        #expect(replies[1].ok)
    }

    @Test func aDifferentProtocolVersionFailsClearly() async throws {
        let server = AgentSocketServer(path: path)
        try server.start()
        defer { server.stop() }
        let path = path
        let outcome = Mutex<AgentErrorCode?>(nil)
        let task = Task { @concurrent in
            do {
                _ = try AgentSocketClient(path: path).connect(timeout: 5)
            } catch let failure as AgentFailure {
                outcome.withLock { $0 = failure.code }
            } catch {
                outcome.withLock { $0 = .failed }
            }
        }
        var hello = AgentHello(appVersion: "test", dataRoot: nil, worldReady: false)
        hello.protocolVersion = AgentProtocol.version + 1
        for _ in 0 ..< 500 {
            for case let .connected(id) in server.poll() {
                server.send(AgentLineCodec.encode(hello), to: id)
            }
            if outcome.withLock({ $0 }) != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        _ = await task.result
        #expect(outcome.withLock { $0 } == .versionMismatch)
    }
}

/// A bare socket client, for bytes the real client would never send.
nonisolated private final class RawSocket {
    private let descriptor: Int32
    private var buffer = AgentLineBuffer()
    private var lines: [Data] = []

    init(path: String) throws {
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, size) }
        }
        guard result == 0 else { throw AgentFailure(.notRunning, "connect") }
    }

    deinit {
        close(descriptor)
    }

    func write(_ text: String) throws {
        let data = Array(text.utf8)
        guard Darwin.write(descriptor, data, data.count) == data.count else {
            throw AgentFailure(.failed, "write")
        }
    }

    func readLine() throws -> Data {
        while lines.isEmpty {
            var chunk = [UInt8](repeating: 0, count: 1024)
            let count = read(descriptor, &chunk, chunk.count)
            guard count > 0 else { throw AgentFailure(.failed, "closed") }
            for case let .line(data) in buffer.append(Data(chunk[0 ..< count])) {
                lines.append(data)
            }
        }
        return lines.removeFirst()
    }
}
