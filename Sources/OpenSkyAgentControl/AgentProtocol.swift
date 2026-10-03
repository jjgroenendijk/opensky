// The wire protocol between `openskycli game` and the app: one JSON object per
// line over a Unix domain socket. The app speaks first with a hello that names
// the protocol version (docs/tools/agent-control.md).

import Foundation

nonisolated public enum AgentProtocol {
    /// Raised on any change a client of the old version would misread.
    public static let version = 1
    /// A longer line is a broken or hostile client, not a request.
    public static let maximumLineBytes = 64 * 1024
}

/// The first line on every connection.
nonisolated public struct AgentHello: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var app: String
    public var appVersion: String
    public var dataRoot: String?
    public var worldReady: Bool

    public init(
        protocolVersion: Int = AgentProtocol.version,
        app: String = "OpenSky",
        appVersion: String,
        dataRoot: String?,
        worldReady: Bool
    ) {
        self.protocolVersion = protocolVersion
        self.app = app
        self.appVersion = appVersion
        self.dataRoot = dataRoot
        self.worldReady = worldReady
    }
}

/// One command. `args` holds the command's named arguments.
nonisolated public struct AgentRequest: Codable, Equatable, Sendable {
    public var id: Int
    public var command: String
    public var args: [String: AgentJSON]

    public init(id: Int = 1, command: String, args: [String: AgentJSON] = [:]) {
        self.id = id
        self.command = command
        self.args = args
    }

    private enum CodingKeys: String, CodingKey {
        case id, command, args
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String: AgentJSON].self, forKey: .args) ?? [:]
    }
}

/// Machine-readable failure kinds. The CLI maps each one to exit code 1.
nonisolated public enum AgentErrorCode: String, Codable, Sendable {
    case malformedRequest
    case unknownCommand
    case invalidArgument
    case notReady
    case notFound
    case unsupported
    case timeout
    case versionMismatch
    case notRunning
    case failed
}

nonisolated public struct AgentFailure: Error, Codable, Equatable, Sendable {
    public var code: AgentErrorCode
    public var message: String

    public init(_ code: AgentErrorCode, _ message: String) {
        self.code = code
        self.message = message
    }
}

/// The answer to one request. Every reply carries the frame, the paused flag
/// and the newest event number, so a client can order what it saw.
nonisolated public struct AgentReply: Codable, Equatable, Sendable {
    public var id: Int
    public var ok: Bool
    public var frame: Int
    public var paused: Bool
    public var eventSeq: Int
    public var result: AgentJSON?
    public var error: AgentFailure?

    public init(
        id: Int,
        context: AgentReplyContext,
        result: AgentJSON? = nil,
        error: AgentFailure? = nil
    ) {
        self.id = id
        ok = error == nil
        frame = context.frame
        paused = context.paused
        eventSeq = context.eventSeq
        self.result = result
        self.error = error
    }
}

/// The clock and event position a reply is stamped with.
nonisolated public struct AgentReplyContext: Equatable, Sendable {
    public var frame: Int
    public var paused: Bool
    public var eventSeq: Int

    public init(frame: Int, paused: Bool, eventSeq: Int) {
        self.frame = frame
        self.paused = paused
        self.eventSeq = eventSeq
    }
}

/// One line the server streams before the final reply of `events --follow`.
nonisolated public struct AgentStreamLine: Codable, Equatable, Sendable {
    public var id: Int
    public var event: AgentEvent

    public init(id: Int, event: AgentEvent) {
        self.id = id
        self.event = event
    }
}

/// Pure encode and decode of single lines, so tests need no socket.
nonisolated public enum AgentLineCodec {
    public static func encode(_ value: some Encodable) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Every type sent here is plain data, so encoding cannot fail.
        var data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// The line as text without its newline. Invalid UTF-8 reads as empty.
    public static func string(_ line: Data) -> String {
        let trimmed = line.last == UInt8(ascii: "\n") ? line.dropLast() : line
        return String(bytes: trimmed, encoding: .utf8) ?? ""
    }

    /// `encode` as text, for printing.
    public static func text(_ value: some Encodable) -> String {
        string(encode(value))
    }

    public static func decodeRequest(_ line: Data) throws(AgentFailure) -> AgentRequest {
        guard line.count <= AgentProtocol.maximumLineBytes else {
            throw AgentFailure(.malformedRequest, "request line over \(line.count) bytes")
        }
        do {
            return try JSONDecoder().decode(AgentRequest.self, from: line)
        } catch {
            throw AgentFailure(.malformedRequest, "request is not a JSON command object")
        }
    }

    public static func decode<Value: Decodable>(
        _ type: Value.Type,
        from line: Data
    ) throws(AgentFailure) -> Value {
        do {
            return try JSONDecoder().decode(type, from: line)
        } catch {
            let text = string(line.prefix(200))
            throw AgentFailure(.malformedRequest, "unreadable line from the app: \(text)")
        }
    }
}

/// Splits a byte stream into lines. Bytes past the line cap are dropped and
/// the line is reported as too long.
nonisolated public struct AgentLineBuffer: Sendable {
    public enum Line: Equatable, Sendable {
        case line(Data)
        case tooLong
    }

    private var pending = Data()
    private var overflowing = false

    public init() {}

    public mutating func append(_ bytes: Data) -> [Line] {
        var lines: [Line] = []
        for byte in bytes {
            if byte == UInt8(ascii: "\n") {
                lines.append(overflowing ? .tooLong : .line(pending))
                pending.removeAll(keepingCapacity: true)
                overflowing = false
            } else if pending.count >= AgentProtocol.maximumLineBytes {
                overflowing = true
            } else {
                pending.append(byte)
            }
        }
        return lines.filter { $0 != .line(Data()) }
    }
}
