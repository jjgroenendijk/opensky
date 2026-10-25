// The thin shell around `ReferenceLaunchPlan`: writes the window size into the
// prefix's `SkyrimPrefs.ini`, then starts Steam and the game. The CLI and the
// launcher page share it.

import Foundation

nonisolated public enum ReferenceLauncherError: Error, Equatable, Sendable, LocalizedError {
    case notReady(String)
    case noWine
    case noWineUser

    public var errorDescription: String? {
        switch self {
        case let .notReady(message): message
        case .noWine: "No Wine found; run make reference-setup."
        case .noWineUser: "The prefix has no Wine user folder; run make reference-setup."
        }
    }
}

nonisolated public enum ReferenceLauncher {
    public static func readyPrefix(_ url: URL? = ReferenceSettings
        .prefix()) throws -> ReferencePrefix
    {
        let status = ReferencePrefixStatus(prefix: url)
        guard status.isReady, let url else { throw ReferenceLauncherError.notReady(status.message) }
        return ReferencePrefix(root: url)
    }

    /// Starts from the game's `High.ini` preset when the game never wrote its own file.
    public static func writePrefsIni(
        prefix: ReferencePrefix,
        width: Int,
        height: Int
    ) throws -> URL {
        guard let ini = prefix.prefsIni() else { throw ReferenceLauncherError.noWineUser }
        let preset = prefix.gameDirectory.appending(path: "High.ini")
        let text = (try? String(contentsOf: ini, encoding: .utf8))
            ?? (try? String(contentsOf: preset, encoding: .utf8)) ?? ""
        try FileManager.default.createDirectory(
            at: ini.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(ReferencePrefsIni.apply(to: text, width: width, height: height).utf8)
            .write(to: ini)
        return ini
    }

    /// Wine runs each Windows program as a process whose command line names it.
    public static func isSteamRunning() -> Bool {
        let pgrep = Process()
        pgrep.executableURL = URL(filePath: "/usr/bin/pgrep")
        pgrep.arguments = ["-i", "-f", "steam.exe"]
        pgrep.standardOutput = FileHandle.nullDevice
        guard (try? pgrep.run()) != nil else { return false }
        pgrep.waitUntilExit()
        return pgrep.terminationStatus == 0
    }

    /// Starts one process detached from the caller, with its output in `log`.
    public static func start(
        _ process: ReferenceProcess, environment: [String: String], log: URL
    ) throws {
        FileManager.default.createFile(atPath: log.path(percentEncoded: false), contents: nil)
        let output = try FileHandle(forWritingTo: log)
        let child = Process()
        child.executableURL = process.executable
        child.arguments = process.arguments
        child.currentDirectoryURL = process.workingDirectory
        child.environment = environment
        child.standardOutput = output
        child.standardError = output
        try child.run()
    }

    /// Starts Steam unless it runs, waits `steamWait` seconds for it, then the game.
    public static func launch(
        prefix: ReferencePrefix, width: Int, height: Int, steamWait: Int, logs: URL
    ) async throws {
        guard let wine = ReferenceSettings.wine() else { throw ReferenceLauncherError.noWine }
        _ = try writePrefsIni(prefix: prefix, width: width, height: height)
        let plan = ReferenceLaunchPlan(
            prefix: prefix, wine: wine, baseEnvironment: ProcessInfo.processInfo.environment
        )
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        if !isSteamRunning() {
            try start(
                plan.steam,
                environment: plan.environment,
                log: logs.appending(path: "steam.log")
            )
            try await Task.sleep(for: .seconds(steamWait))
        }
        try start(plan.game, environment: plan.environment, log: logs.appending(path: "game.log"))
    }

    /// The newest `.ess` the reference game wrote, for an import into OpenSky.
    public static func newestSave(in prefix: ReferencePrefix) -> URL? {
        guard let saves = prefix.savesDirectory() else { return nil }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: saves, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files.filter { $0.pathExtension.lowercased() == "ess" }.max { lhs, rhs in
            let left = try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
            let right = try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
            return (left?.contentModificationDate ?? .distantPast)
                < (right?.contentModificationDate ?? .distantPast)
        }
    }
}
