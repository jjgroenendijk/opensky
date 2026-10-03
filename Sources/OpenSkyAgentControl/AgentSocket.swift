// Where the control socket lives and the POSIX calls both ends share. Only
// the user can open it: the folder is 0700 and the socket 0600.

import Darwin
import Foundation

nonisolated public enum AgentSocketLocation {
    /// Tests and a second checkout point the app and the CLI at another path.
    public static let environmentKey = "OPENSKY_AGENT_SOCKET"
    public static let fileName = "agent-control.sock"

    public static func path(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let override = environment[environmentKey], !override.isEmpty {
            return override
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: "Library/Application Support/OpenSky/\(fileName)")
            .path(percentEncoded: false)
    }
}

/// The shared socket calls. A failure carries `errno` text.
nonisolated enum AgentSocketCalls {
    /// `sun_path` holds 104 bytes with the terminating zero.
    static let maximumPathBytes = 103

    static func makeSocket() throws(AgentFailure) -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw failure("socket") }
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return descriptor
    }

    /// Calls `body` with a filled `sockaddr_un` for `path`.
    static func withAddress<Result>(
        _ path: String,
        _ body: (UnsafePointer<sockaddr>, socklen_t) -> Result
    ) throws(AgentFailure) -> Result {
        let bytes = Array(path.utf8)
        guard !bytes.isEmpty, bytes.count <= maximumPathBytes else {
            throw AgentFailure(.invalidArgument, "socket path is empty or over 103 bytes: \(path)")
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    static func setNonBlocking(_ descriptor: Int32) {
        let flags = fcntl(descriptor, F_GETFL)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
    }

    /// Reads what is there without blocking. Nil means the peer closed.
    static func readAvailable(_ descriptor: Int32) -> Data? {
        var collected = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                collected.append(contentsOf: buffer[0 ..< count])
                continue
            }
            if count == 0 {
                return collected.isEmpty ? nil : collected
            }
            return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ? collected : nil
        }
    }

    /// Writes as much as the socket takes now and returns the rest.
    /// Nil means the peer is gone.
    static func writeAvailable(_ descriptor: Int32, _ data: Data) -> Data? {
        var remaining = data
        while !remaining.isEmpty {
            let count = remaining.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                remaining.removeFirst(count)
                continue
            }
            return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ? remaining : nil
        }
        return remaining
    }

    static func failure(_ call: String, code: AgentErrorCode = .failed) -> AgentFailure {
        AgentFailure(code, "\(call) failed: \(String(cString: strerror(errno)))")
    }
}
