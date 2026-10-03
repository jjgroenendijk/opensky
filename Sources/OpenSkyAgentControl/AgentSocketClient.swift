// The CLI end of the control socket: blocking calls with timeouts, because a
// CLI call does one thing and exits. Not tied to the main actor, so a test can
// run it beside a polled server.

import Darwin
import Foundation

nonisolated public final class AgentSocketClient {
    public let path: String
    private var descriptor: Int32 = -1
    private var buffer = AgentLineBuffer()
    private var lines: [Data] = []

    public init(path: String) {
        self.path = path
    }

    deinit {
        disconnect()
    }

    /// Connects and checks the hello. A missing or dead socket is `notRunning`.
    public func connect(timeout: Double) throws(AgentFailure) -> AgentHello {
        disconnect()
        let socket = try AgentSocketCalls.makeSocket()
        let result = try AgentSocketCalls.withAddress(path) { Darwin.connect(socket, $0, $1) }
        guard result == 0 else {
            close(socket)
            throw AgentFailure(
                .notRunning,
                "the OpenSky app is not running with agent control on (no server at \(path))"
            )
        }
        descriptor = socket
        let hello = try AgentLineCodec.decode(AgentHello.self, from: readLine(timeout: timeout))
        guard hello.protocolVersion == AgentProtocol.version else {
            disconnect()
            throw AgentFailure(
                .versionMismatch,
                "the app speaks protocol \(hello.protocolVersion), this CLI speaks "
                    + "\(AgentProtocol.version); rebuild both from one checkout"
            )
        }
        return hello
    }

    public func send(_ request: AgentRequest) throws(AgentFailure) {
        var data = AgentLineCodec.encode(request)
        while !data.isEmpty {
            let count = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            guard count > 0 else { throw AgentSocketCalls.failure("write") }
            data.removeFirst(count)
        }
    }

    /// Blocks until one full line arrives or `timeout` seconds pass.
    public func readLine(timeout: Double) throws(AgentFailure) -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        while lines.isEmpty {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                throw AgentFailure(.timeout, "no reply from the app within \(Int(timeout)) s")
            }
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&poller, 1, Int32(min(remaining, 1) * 1000))
            if ready < 0, errno != EINTR {
                throw AgentSocketCalls.failure("poll")
            }
            guard ready > 0 else { continue }
            try receive()
        }
        return lines.removeFirst()
    }

    public func disconnect() {
        guard descriptor >= 0 else { return }
        close(descriptor)
        descriptor = -1
        buffer = AgentLineBuffer()
        lines.removeAll()
    }

    private func receive() throws(AgentFailure) {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let count = chunk.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
        guard count > 0 else {
            throw AgentFailure(.notRunning, "the app closed the connection")
        }
        for line in buffer.append(Data(chunk[0 ..< count])) {
            guard case let .line(data) = line else {
                throw AgentFailure(.malformedRequest, "the app sent a line over the size cap")
            }
            lines.append(data)
        }
    }
}
