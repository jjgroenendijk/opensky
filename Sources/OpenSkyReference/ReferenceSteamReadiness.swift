// When a Steam the launcher started can take the game. A game that starts too early fails
// the Steam API check and restarts through Steam, which opens the game's launcher window
// instead (docs/tools/reference-game.md).

import Foundation

/// Reads Steam's own logs: `console_log.txt` gets the start-up line once the client is up,
/// and `connection_log.txt` gets the logon line once the account is logged on.
nonisolated public struct ReferenceSteamReadiness: Equatable, Sendable {
    public static let startedLine = "System startup time:"
    public static let loggedOnLine = "RecvMsgClientLogOnResponse() : processing complete"
    /// A game 2 s after both lines restarted through Steam; one 13 s after started.
    public static let settleSeconds = 10

    /// The byte length of each log before Steam starts, so only this start's lines count.
    public var consoleOffset: UInt64
    public var connectionOffset: UInt64

    public init(consoleOffset: UInt64, connectionOffset: UInt64) {
        self.consoleOffset = consoleOffset
        self.connectionOffset = connectionOffset
    }

    /// `console` and `connection` are the text each log gained since its offset.
    public static func isReady(console: String, connection: String) -> Bool {
        console.contains(startedLine) && connection.contains(loggedOnLine)
    }

    public static func consoleLog(_ prefix: ReferencePrefix) -> URL {
        prefix.steamDirectory.appending(path: "logs/console_log.txt")
    }

    public static func connectionLog(_ prefix: ReferencePrefix) -> URL {
        prefix.steamDirectory.appending(path: "logs/connection_log.txt")
    }

    /// Notes where both logs end now, before Steam starts.
    public static func mark(_ prefix: ReferencePrefix) -> ReferenceSteamReadiness {
        ReferenceSteamReadiness(
            consoleOffset: length(consoleLog(prefix)),
            connectionOffset: length(connectionLog(prefix))
        )
    }

    /// True once Steam wrote both lines after `mark`.
    public func isReady(_ prefix: ReferencePrefix) -> Bool {
        Self.isReady(
            console: Self.text(Self.consoleLog(prefix), after: consoleOffset),
            connection: Self.text(Self.connectionLog(prefix), after: connectionOffset)
        )
    }

    private static func length(_ url: URL) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false)
        )
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// A log shorter than `offset` was started again, so all of it is new.
    private static func text(_ url: URL, after offset: UInt64) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let start = length(url) < offset ? 0 : offset
        guard
            (try? handle.seek(toOffset: start)) != nil,
            let data = try? handle.readToEnd()
        else { return "" }
        // Latin-1 reads any bytes, and both lines are plain ASCII.
        return String(bytes: data, encoding: .isoLatin1) ?? ""
    }
}
