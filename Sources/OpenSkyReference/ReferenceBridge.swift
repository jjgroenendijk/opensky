// The file channel to the OpenSkyBridge plugin inside the Windows game. OpenSky drops
// command batches into `OpenSkyBridge/commands/`; the plugin runs them and rewrites
// `OpenSkyBridge/state.json` four times a second (docs/tools/reference-game.md).

import Foundation

nonisolated public enum ReferenceBridgeError: Error, Equatable, Sendable, LocalizedError {
    case notRunning
    case timedOut(String)
    case noDialog
    case noSuchButton(String, [String])

    public var errorDescription: String? {
        switch self {
        case .notRunning:
            "The Windows game's bridge is not running. Start the game with "
                + "make reference-game, after make reference-bridge."
        case let .timedOut(what): "The Windows game did not \(what) in time."
        case .noDialog: "The Windows game shows no message box."
        case let .noSuchButton(button, buttons):
            "The message box has no button \(button). "
                + "Its buttons: \(buttons.joined(separator: ", "))."
        }
    }
}

nonisolated public struct ReferenceBridge: Sendable {
    public static let folderName = "OpenSkyBridge"
    /// The plugin rewrites the state every 0.25 s, so an older file means the game is gone.
    public static let liveSeconds: TimeInterval = 3

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public init(prefix: ReferencePrefix) {
        self.init(folder: prefix.bridgeDirectory)
    }

    var stateFile: URL {
        folder.appending(path: "state.json")
    }

    var commandsFolder: URL {
        folder.appending(path: "commands", directoryHint: .isDirectory)
    }

    /// The game's state, or nil when no running game wrote it in the last few seconds.
    public func state(now: Date = Date()) -> ReferenceBridgeState? {
        let path = stateFile.path(percentEncoded: false)
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            let written = attributes[.modificationDate] as? Date,
            now.timeIntervalSince(written) < Self.liveSeconds,
            let data = FileManager.default.contents(atPath: path)
        else { return nil }
        return try? JSONDecoder().decode(ReferenceBridgeState.self, from: data)
    }

    /// Writes one batch under a name that sorts after every earlier one, and returns it.
    /// The plugin reads only `.txt` files, so the rename makes the batch appear whole.
    @discardableResult
    public func send(_ lines: [String], at date: Date = Date()) throws -> String {
        let name = Self.batchName(at: date)
        try FileManager.default.createDirectory(
            at: commandsFolder, withIntermediateDirectories: true
        )
        let partial = commandsFolder.appending(path: "\(name).tmp")
        try Data(lines.map { $0 + "\r\n" }.joined().utf8).write(to: partial)
        try FileManager.default.moveItem(
            at: partial, to: commandsFolder.appending(path: "\(name).txt")
        )
        return name
    }

    static func batchName(at date: Date) -> String {
        let milliseconds = UInt64(max(0, date.timeIntervalSince1970) * 1000)
        let digits = String(milliseconds)
        let suffix = String(UInt16.random(in: 0 ... .max), radix: 16)
        return String(repeating: "0", count: max(0, 16 - digits.count)) + digits + "-" + suffix
    }

    /// Removes the state and the batches an earlier run left, before the game starts again.
    public func reset() {
        try? FileManager.default.removeItem(at: stateFile)
        try? FileManager.default.removeItem(at: commandsFolder)
    }

    /// Polls the state until `done` holds; `what` names the wait in the timeout error.
    public func wait(
        _ what: String, timeout: Duration,
        until done: (ReferenceBridgeState) -> Bool
    ) async throws -> ReferenceBridgeState {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let state = state(), done(state) {
                return state
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw ReferenceBridgeError.timedOut(what)
    }

    /// Sends the lines and waits until the game has run them.
    @discardableResult
    public func run(_ lines: [String], timeout: Duration = .seconds(10)) async throws
        -> ReferenceBridgeState
    {
        guard state() != nil else { throw ReferenceBridgeError.notRunning }
        let name = try send(lines)
        return try await wait("run the commands", timeout: timeout) { $0.batch == name }
    }
}

nonisolated extension ReferencePrefix {
    /// The folder the bridge plugin and OpenSky share, beside `SkyrimSE.exe`.
    public var bridgeDirectory: URL {
        gameDirectory.appending(path: ReferenceBridge.folderName, directoryHint: .isDirectory)
    }
}

/// What the bridge still lacks in the game copy; `make reference-bridge` installs each part.
nonisolated public enum ReferenceBridgePart: String, CaseIterable, Sendable {
    case scriptExtender = "SKSE (skse64_loader.exe)"
    case addressLibrary = "the Address Library (Data/SKSE/Plugins/versionlib-*.bin)"
    case plugin = "the bridge plugin (Data/SKSE/Plugins/OpenSkyBridge.dll)"

    public static func missing(in prefix: ReferencePrefix) -> [Self] {
        let plugins = prefix.bridgePlugin.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(
            atPath: plugins.path(percentEncoded: false)
        )) ?? []
        return missing(
            names: Set(names.map { $0.lowercased() }),
            hasLoader: FileManager.default.fileExists(
                atPath: prefix.scriptExtenderLoader.path(percentEncoded: false)
            )
        )
    }

    /// `names` are the lower-case file names in `Data/SKSE/Plugins`.
    static func missing(names: Set<String>, hasLoader: Bool) -> [Self] {
        allCases.filter { part in
            switch part {
            case .scriptExtender: !hasLoader
            case .addressLibrary:
                !names.contains { $0.hasPrefix("versionlib-") && $0.hasSuffix(".bin") }
            case .plugin: !names.contains("openskybridge.dll")
            }
        }
    }
}
