// The thin shell around `ReferenceLaunchPlan`: writes the window frame into the
// prefix's `SkyrimPrefs.ini`, repairs Steam's browser, then starts Steam and the
// game. The CLI and the launcher page share it.

import Foundation
import OpenSkyGameData

nonisolated public enum ReferenceLauncherError: Error, Equatable, Sendable, LocalizedError {
    case notReady(String)
    case noWine
    case noWineUser
    case noWrapper
    case outsidePrefix(String)

    public var errorDescription: String? {
        switch self {
        case let .notReady(message): message
        case .noWine: "No Wine found; run make reference-setup."
        case .noWineUser: "The prefix has no Wine user folder; run make reference-setup."
        case .noWrapper: "The prefix has no Steam web helper wrapper; run make reference-setup."
        case let .outsidePrefix(path):
            "Wine links this folder outside the prefix; run make reference-setup: \(path)"
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
    /// A `preset` sets every value its file names, such as Low when two games share the GPU.
    public static func writePrefsIni(
        prefix: ReferencePrefix, frame: ReferenceWindowFrame, preset: GraphicsPreset? = nil
    ) throws -> URL {
        guard let ini = prefix.prefsIni() else { throw ReferenceLauncherError.noWineUser }
        try requireInsidePrefix(ini.deletingLastPathComponent(), prefix: prefix)
        func read(_ url: URL) -> String? {
            try? String(contentsOf: url, encoding: .utf8)
        }
        let high = prefix.gameDirectory.appending(path: GraphicsPreset.high.fileName)
        var text = read(ini) ?? read(high) ?? ""
        if let preset {
            let file = prefix.gameDirectory.appending(path: preset.fileName)
            text = ReferencePrefsIni.apply(preset: read(file) ?? "", to: text)
        }
        try FileManager.default.createDirectory(
            at: ini.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(ReferencePrefsIni.apply(to: text, frame: frame).utf8).write(to: ini)
        return ini
    }

    /// Starts from the game's `Skyrim_Default.ini`, as the game does when the file is missing.
    public static func writeGameIni(prefix: ReferencePrefix) throws {
        guard let ini = prefix.gameIni() else { throw ReferenceLauncherError.noWineUser }
        try requireInsidePrefix(ini.deletingLastPathComponent(), prefix: prefix)
        let fallback = prefix.gameDirectory.appending(path: "Skyrim_Default.ini")
        let text = (try? String(contentsOf: ini, encoding: .utf8))
            ?? (try? String(contentsOf: fallback, encoding: .utf8)) ?? ""
        try FileManager.default.createDirectory(
            at: ini.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(ReferencePrefsIni.applyGameIni(to: text).utf8).write(to: ini)
    }

    /// Wine's default links the user's `Documents` to the macOS home folder; a write
    /// through such a link would leave the prefix.
    static func requireInsidePrefix(_ folder: URL, prefix: ReferencePrefix) throws {
        var existing = folder
        while
            !FileManager.default.fileExists(atPath: existing.path(percentEncoded: false)),
            existing.pathComponents.count > 1
        {
            existing.deleteLastPathComponent()
        }
        let resolved = existing.resolvingSymlinksInPath().path(percentEncoded: false)
        let root = prefix.root.resolvingSymlinksInPath().path(percentEncoded: false)
        guard resolved.hasPrefix(root) else {
            throw ReferenceLauncherError.outsidePrefix(resolved)
        }
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
        prefix: ReferencePrefix, options: ReferenceLaunchOptions, logs: URL
    ) async throws {
        guard let wine = ReferenceSettings.wine(prefix: prefix.root) else {
            throw ReferenceLauncherError.noWine
        }
        _ = try writePrefsIni(prefix: prefix, frame: options.frame, preset: options.preset)
        try writeGameIni(prefix: prefix)
        func exists(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        }
        let plan = ReferenceLaunchPlan(
            prefix: prefix, wine: wine, baseEnvironment: ProcessInfo.processInfo.environment,
            clientDownloaded: exists(prefix.steamUI),
            scriptExtender: exists(prefix.scriptExtenderLoader)
        )
        ReferenceBridge(prefix: prefix).reset()
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        if !isSteamRunning() {
            ReferenceSteamRepair.removeBrowserLocks(prefix: prefix)
            try ReferenceSteamRepair.deployWrapper(prefix: prefix)
            try start(
                plan.steam,
                environment: plan.environment,
                log: logs.appending(path: "steam.log")
            )
            try await Task.sleep(for: .seconds(options.steamWait))
        }
        try start(
            plan.game,
            environment: plan.gameEnvironment,
            log: logs.appending(path: "game.log")
        )
    }

    /// The newest `.ess` the reference game wrote, for an import into OpenSky.
    public static func newestSave(in prefix: ReferencePrefix) -> URL? {
        saves(in: prefix).first
    }

    /// Every `.ess` the reference game wrote, newest first.
    public static func saves(in prefix: ReferencePrefix) -> [URL] {
        guard let saves = prefix.savesDirectory() else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: saves, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        func written(_ url: URL) -> Date {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return values?.contentModificationDate ?? .distantPast
        }
        return files.filter { $0.pathExtension.lowercased() == "ess" }
            .sorted { written($0) > written($1) }
    }
}

nonisolated public struct ReferenceLaunchOptions: Equatable, Sendable {
    public var frame: ReferenceWindowFrame
    /// Seconds to wait for a newly started Steam to log in before the game starts.
    public var steamWait: Int
    /// The game's own preset to apply first; `nil` keeps the current graphics settings.
    public var preset: GraphicsPreset?

    public init(frame: ReferenceWindowFrame, steamWait: Int, preset: GraphicsPreset? = nil) {
        self.frame = frame
        self.steamWait = steamWait
        self.preset = preset
    }
}
