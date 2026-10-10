// Writes this run's OpenSky log entries to a file in `~/Library/Logs/OpenSky`,
// so a player can attach them to a problem report. The engine logs only to the
// unified log, which a player cannot easily read.

import Foundation
import OSLog

nonisolated public enum SessionLogExport {
    public static let subsystem = "nl.jjgroenendijk.opensky"

    public static func folder(fileManager: FileManager = .default) throws -> URL {
        try fileManager
            .url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Logs", directoryHint: .isDirectory)
            .appending(path: "OpenSky", directoryHint: .isDirectory)
    }

    /// One line per entry: `2026-10-09T20:52:24Z [CellStream] message`.
    public static func line(date: Date, category: String, message: String) -> String {
        "\(date.ISO8601Format()) [\(category)] \(message)"
    }

    /// The file it wrote. Reads the log of this process only.
    @concurrent
    public static func export(now: Date = Date()) async throws -> URL {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(matching: NSPredicate(
            format: "subsystem == %@",
            subsystem
        ))
        let lines = entries.compactMap { entry -> String? in
            guard let entry = entry as? OSLogEntryLog else { return nil }
            return line(date: entry.date, category: entry.category, message: entry.composedMessage)
        }
        let folder = try folder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = now.ISO8601Format().replacingOccurrences(of: ":", with: "-")
        let url = folder.appending(path: "opensky-\(stamp).log")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
