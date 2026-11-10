import Foundation
public import OSLog
import Synchronization

/// An `os.Logger` that also keeps error and fault lines in `EngineLogTap`, so the
/// agent event stream reads them without querying the system log store.
nonisolated public struct EngineLogger: Sendable {
    private let logger: Logger
    private let category: String

    public init(subsystem: String, category: String) {
        logger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }

    public func debug(_ message: EngineLogMessage) {
        logger.debug("\(message.text, privacy: .public)")
    }

    public func info(_ message: EngineLogMessage) {
        logger.info("\(message.text, privacy: .public)")
    }

    public func notice(_ message: EngineLogMessage) {
        logger.notice("\(message.text, privacy: .public)")
    }

    public func warning(_ message: EngineLogMessage) {
        logger.warning("\(message.text, privacy: .public)")
    }

    public func error(_ message: EngineLogMessage) {
        logger.error("\(message.text, privacy: .public)")
        EngineLogTap.record(category: category, message: message.text)
    }

    public func fault(_ message: EngineLogMessage) {
        logger.fault("\(message.text, privacy: .public)")
        EngineLogTap.record(category: category, message: message.text)
    }
}

/// Only `.public` exists: the game logs nothing private, and the parameter keeps
/// `os.Logger` call sites unchanged.
nonisolated public enum EngineLogPrivacy: Sendable {
    case `public`
}

nonisolated public struct EngineLogMessage: ExpressibleByStringInterpolation, Sendable {
    public struct StringInterpolation: StringInterpolationProtocol {
        var text = ""

        public init(literalCapacity: Int, interpolationCount _: Int) {
            text.reserveCapacity(literalCapacity)
        }

        public mutating func appendLiteral(_ literal: String) {
            text += literal
        }

        public mutating func appendInterpolation(_ value: some Any, privacy _: EngineLogPrivacy) {
            text += String(describing: value)
        }

        public mutating func appendInterpolation(_ value: some Any) {
            text += String(describing: value)
        }
    }

    public let text: String

    public init(stringLiteral value: String) {
        text = value
    }

    public init(stringInterpolation: StringInterpolation) {
        text = stringInterpolation.text
    }
}

nonisolated public struct EngineLogLine: Equatable, Sendable {
    public let category: String
    public let message: String
}

/// Error and fault lines since the last `drain()`, oldest first. It keeps the newest
/// `limit` lines, so a process nobody drains does not grow.
nonisolated public enum EngineLogTap {
    static let limit = 512
    private static let lines = Mutex(EngineLogRing(limit: limit))

    static func record(category: String, message: String) {
        lines.withLock { $0.append(EngineLogLine(category: category, message: message)) }
    }

    public static func drain() -> [EngineLogLine] {
        lines.withLock { $0.drain(category: nil) }
    }

    static func drain(category: String) -> [EngineLogLine] {
        lines.withLock { $0.drain(category: category) }
    }
}

nonisolated struct EngineLogRing: Sendable {
    let limit: Int
    private var lines: [EngineLogLine] = []

    init(limit: Int) {
        self.limit = limit
    }

    mutating func append(_ line: EngineLogLine) {
        lines.append(line)
        if lines.count > limit {
            lines.removeFirst(lines.count - limit)
        }
    }

    /// Removes and returns the lines of `category`, or every line for nil.
    mutating func drain(category: String?) -> [EngineLogLine] {
        guard let category else {
            defer { lines.removeAll(keepingCapacity: true) }
            return lines
        }
        let drained = lines.filter { $0.category == category }
        lines.removeAll { $0.category == category }
        return drained
    }
}
