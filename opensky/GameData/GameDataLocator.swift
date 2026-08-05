// Locates the user's Skyrim Special Edition install on disk. The install is
// read-only external input — never bundled, never copied (AGENTS.md, Legal & IP).
//
// Resolution order (first configured source wins; a configured-but-invalid
// override fails loud instead of falling through):
//   1. OPENSKY_DATA_ROOT environment variable (tests, CLI runs)
//   2. UserDefaults key "OpenSkyDataRoot" (persistent per-machine setting)
//   3. Default Steam library path under ~/Library/Application Support
//
// Inside an XCTest host only source 1 applies: see `persistedRootDefaults`.

import Foundation

nonisolated enum GameDataError: Error, Equatable {
    /// An explicit override (env var or defaults) points at something that is
    /// not a Skyrim SE install. Overrides never fall through to other sources.
    case overrideInvalid(source: GameDataRoot.Source, path: String)
    /// No override set and the default Steam path holds no install.
    case notFound(searched: [String])
}

nonisolated extension GameDataError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .overrideInvalid(source, path):
            let origin = switch source {
            case .environment: "environment variable \(GameDataLocator.environmentKey)"
            case .userDefaults: "defaults key \(GameDataLocator.defaultsKey)"
            case .steamDefault: "default Steam path"
            }
            return "Configured game data root (\(origin)) is not a Skyrim SE install: \(path). "
                + "Expected a folder containing Data/Skyrim.esm (or Skyrim.esm itself)."
        case let .notFound(searched):
            let scope = searched.isEmpty
                ? "No fallback location was consulted."
                : "Searched: " + searched.joined(separator: ", ") + "."
            return "Skyrim Special Edition install not found. \(scope) "
                + "Set the \(GameDataLocator.defaultsKey) default or the "
                + "\(GameDataLocator.environmentKey) environment variable to the install folder."
        }
    }
}

/// A validated Skyrim SE install location.
nonisolated struct GameDataRoot: Equatable {
    enum Source: Equatable {
        case environment
        case userDefaults
        case steamDefault
    }

    /// Install root (the folder holding the game executable and `Data/`).
    let installURL: URL
    /// `Data/` folder — plugins, archives, loose files. All engine reads go under here.
    let dataURL: URL
    let source: Source
}

nonisolated enum GameDataLocator {
    static let environmentKey = "OPENSKY_DATA_ROOT"
    static let defaultsKey = "OpenSkyDataRoot"

    /// Defaults domain holding the data-root setting. One shared domain so
    /// every tool (app, preview, CLI) sees the same setting regardless of its
    /// own bundle id.
    static let settingsDomain = "nl.jjgroenendijk.opensky"

    /// Defaults store for the data-root setting. `UserDefaults(suiteName:)`
    /// rejects the current app's own bundle id, so the main app (whose domain
    /// IS the shared one) uses `.standard` — same plist either way.
    static var settingsDefaults: UserDefaults {
        if Bundle.main.bundleIdentifier == settingsDomain {
            return .standard
        }
        return UserDefaults(suiteName: settingsDomain) ?? .standard
    }

    /// Steam's default install location for Skyrim SE on macOS.
    static var defaultSteamInstallURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Steam/steamapps/common")
            .appending(path: "Skyrim Special Edition")
    }

    /// True inside a unit-test host. The host is the app bundle itself, so it
    /// inherits the developer's app settings and home directory (issue #362).
    static var isRunningInTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Defaults `locate` consults for a persisted root, or nil when no source
    /// applies. A test host withholds it: the host shares the app's defaults
    /// domain, so a machine where the app has been pointed at a real install
    /// would feed that install to unit tests meant to be install-independent —
    /// which is how `make test` came to block in `open()` on an external
    /// volume. Real-data suites gate on the environment variable instead.
    static var persistedRootDefaults: UserDefaults? {
        isRunningInTestHost ? nil : settingsDefaults
    }

    /// Fallback install `locate` consults, or nil when no source applies.
    /// Withheld in a test host for the same reason as `persistedRootDefaults`:
    /// on a machine with a stock Steam library it is the developer's real
    /// install.
    static var defaultInstallCandidate: URL? {
        isRunningInTestHost ? nil : defaultSteamInstallURL
    }

    /// Resolves and validates the game data root. Every source is injectable
    /// for tests; production callers use the defaults. A nil `userDefaults` or
    /// `defaultInstall` skips that source entirely.
    static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults? = persistedRootDefaults,
        defaultInstall: URL? = defaultInstallCandidate,
        fileManager: FileManager = .default
    ) throws -> GameDataRoot {
        if let path = environment[environmentKey], !path.isEmpty {
            return try validated(path: path, source: .environment, fileManager: fileManager)
        }
        if let path = userDefaults?.string(forKey: defaultsKey), !path.isEmpty {
            return try validated(path: path, source: .userDefaults, fileManager: fileManager)
        }
        if
            let defaultInstall,
            let root = root(at: defaultInstall, source: .steamDefault, fileManager: fileManager)
        {
            return root
        }
        throw GameDataError.notFound(
            searched: defaultInstall.map { [$0.path(percentEncoded: false)] } ?? []
        )
    }

    /// Persists a user-chosen install path (Settings UI). Validated first;
    /// an invalid choice throws and leaves the stored setting untouched.
    @discardableResult
    static func saveUserChoice(
        path: String,
        userDefaults: UserDefaults = settingsDefaults,
        fileManager: FileManager = .default
    ) throws -> GameDataRoot {
        let root = try validated(path: path, source: .userDefaults, fileManager: fileManager)
        userDefaults.set(path, forKey: defaultsKey)
        return root
    }

    /// Removes the persisted choice; the next locate falls back to the
    /// default Steam path.
    static func clearUserChoice(userDefaults: UserDefaults = settingsDefaults) {
        userDefaults.removeObject(forKey: defaultsKey)
    }

    private static func validated(
        path: String,
        source: GameDataRoot.Source,
        fileManager: FileManager
    ) throws -> GameDataRoot {
        let expanded = NSString(string: path).expandingTildeInPath
        let url = URL(filePath: expanded, directoryHint: .isDirectory)
        guard let root = root(at: url, source: source, fileManager: fileManager) else {
            throw GameDataError.overrideInvalid(source: source, path: path)
        }
        return root
    }

    /// Accepts either the install root (contains `Data/Skyrim.esm`) or the
    /// `Data/` folder itself (contains `Skyrim.esm`) — users configure both.
    private static func root(
        at url: URL,
        source: GameDataRoot.Source,
        fileManager: FileManager
    ) -> GameDataRoot? {
        let dataURL = url.appending(path: "Data", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: dataURL.appending(path: "Skyrim.esm").path) {
            return GameDataRoot(installURL: url, dataURL: dataURL, source: source)
        }
        if fileManager.fileExists(atPath: url.appending(path: "Skyrim.esm").path) {
            return GameDataRoot(
                installURL: url.deletingLastPathComponent(),
                dataURL: url,
                source: source
            )
        }
        return nil
    }
}
