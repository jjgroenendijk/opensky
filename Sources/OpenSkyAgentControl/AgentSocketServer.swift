// The app end of the control socket. Non-blocking: the host polls it on the
// main actor, so no thread or queue is involved (docs/decisions/concurrency.md).

import Darwin
import Foundation

nonisolated public enum AgentSocketEvent: Equatable, Sendable {
    case connected(Int)
    case line(Int, Data)
    case lineTooLong(Int)
    case disconnected(Int)
}

public final class AgentSocketServer {
    private struct Client {
        let descriptor: Int32
        var buffer = AgentLineBuffer()
        var outbox = Data()
    }

    public let path: String
    private var listener: Int32 = -1
    private var clients: [Int: Client] = [:]
    private var nextClientID = 1

    public init(path: String) {
        self.path = path
    }

    public var connectionCount: Int {
        clients.count
    }

    public func start() throws(AgentFailure) {
        guard listener < 0 else { return }
        try prepareFolder()
        try removeStaleSocket()
        let descriptor = try AgentSocketCalls.makeSocket()
        let bound = try AgentSocketCalls.withAddress(path) { bind(descriptor, $0, $1) }
        guard bound == 0, chmod(path, 0o600) == 0, listen(descriptor, 8) == 0 else {
            let failure = AgentSocketCalls.failure("bind \(path)")
            close(descriptor)
            unlink(path)
            throw failure
        }
        AgentSocketCalls.setNonBlocking(descriptor)
        listener = descriptor
    }

    public func stop() {
        for client in clients.values {
            close(client.descriptor)
        }
        clients.removeAll()
        guard listener >= 0 else { return }
        close(listener)
        listener = -1
        unlink(path)
    }

    /// Accepts, reads, and flushes once. Never blocks.
    public func poll() -> [AgentSocketEvent] {
        guard listener >= 0 else { return [] }
        var events = acceptPending()
        for id in clients.keys.sorted() {
            events += readClient(id)
        }
        flush()
        return events
    }

    public func send(_ data: Data, to id: Int) {
        clients[id]?.outbox.append(data)
        flush()
    }

    private func acceptPending() -> [AgentSocketEvent] {
        var events: [AgentSocketEvent] = []
        while true {
            let descriptor = accept(listener, nil, nil)
            guard descriptor >= 0 else { break }
            var on: Int32 = 1
            setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &on,
                socklen_t(MemoryLayout<Int32>.size)
            )
            AgentSocketCalls.setNonBlocking(descriptor)
            let id = nextClientID
            nextClientID += 1
            clients[id] = Client(descriptor: descriptor)
            events.append(.connected(id))
        }
        return events
    }

    private func readClient(_ id: Int) -> [AgentSocketEvent] {
        guard var client = clients[id] else { return [] }
        guard let bytes = AgentSocketCalls.readAvailable(client.descriptor) else {
            drop(id)
            return [.disconnected(id)]
        }
        let lines = client.buffer.append(bytes)
        clients[id] = client
        return lines.map { line in
            switch line {
            case let .line(data): .line(id, data)
            case .tooLong: .lineTooLong(id)
            }
        }
    }

    private func flush() {
        for (id, client) in clients {
            var updated = client
            if !client.outbox.isEmpty {
                guard let rest = AgentSocketCalls.writeAvailable(client.descriptor, client.outbox)
                else {
                    drop(id)
                    continue
                }
                updated.outbox = rest
            }
            clients[id] = updated
        }
    }

    private func drop(_ id: Int) {
        guard let client = clients.removeValue(forKey: id) else { return }
        close(client.descriptor)
    }

    private func prepareFolder() throws(AgentFailure) {
        let folder = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(
                atPath: folder,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw AgentFailure(.failed, "cannot create \(folder): \(error.localizedDescription)")
        }
    }

    /// A socket file left by a crashed app is removed. A live one means a
    /// second app already serves this path.
    private func removeStaleSocket() throws(AgentFailure) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let probe = try AgentSocketCalls.makeSocket()
        defer { close(probe) }
        let connected = try AgentSocketCalls.withAddress(path) { connect(probe, $0, $1) }
        guard connected != 0 else {
            throw AgentFailure(.failed, "another OpenSky app already serves \(path)")
        }
        unlink(path)
    }
}
