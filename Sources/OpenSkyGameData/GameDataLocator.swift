// Locates the user's Skyrim SE install, read-only (AGENTS.md, Legal & IP). First
// configured source wins, and an invalid one fails loud: `OPENSKY_DATA_ROOT`, then
// UserDefaults "OpenSkyDataRoot", then the default Steam path, then every Steam library.
// A test host reads only the environment variable (`persistedRootDefaults`).

import Foundation

nonisolated public enum GameDataError: Error, Equatable, Sendable {
    /// An explicit override (env var or defaults) points at something that is
    /// not a Skyrim SE install. Overrides never fall through to other sources.
    case overrideInvalid(source: GameDataRoot.Source, path: String)
    /// No override set and the default Steam path holds no install.
    case notFound(searched: [String])
}

nonisolated extension GameDataError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .overrideInvalid(source, path):
            let origin = switch source {
            case .environment: "the \(GameDataLocator.environmentKey) environment variable"
            case .userDefaults: "the folder chosen in Settings"
            case .steamDefault, .steamLibrary: "the Steam folder"
            }
            return "The game folder set by \(origin) has no Skyrim Special Edition in it: "
                + "\(path). Choose the folder that holds Data/Skyrim.esm in Settings."
        case let .notFound(searched):
            let scope = searched.isEmpty
                ? "No folder was searched."
                : "Searched: " + searched.joined(separator: ", ") + "."
            return "Skyrim Special Edition was not found. \(scope) "
                + "Choose the game folder in Settings: it holds Data/Skyrim.esm."
        }
    }
}

/// A validated Skyrim SE install location.
nonisolated public struct GameDataRoot: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case environment
        case userDefaults
        case steamDefault
        case steamLibrary
    }

    /// Install root (the folder holding the game executable and `Data/`).
    public let installURL: URL
    /// `Data/` folder — plugins, archives, loose files. All engine reads go under here.
    public let dataURL: URL
    public let source: Source
}

nonisolated public enum GameDataLocator: Sendable {
    public static let environmentKey = "OPENSKY_DATA_ROOT"
    public static let defaultsKey = "OpenSkyDataRoot"

    /// Defaults domain holding the data-root setting. One shared domain so
    /// every tool (app, preview, CLI) sees the same setting regardless of its
    /// own bundle id.
    public static let settingsDomain = "nl.jjgroenendijk.opensky"

    /// Defaults store for the data-root setting. `UserDefaults(suiteName:)`
    /// rejects the current app's own bundle id, so the main app (whose domain
    /// IS the shared one) uses `.standard` — same plist either way.
    public static var settingsDefaults: UserDefaults {
        if Bundle.main.bundleIdentifier == settingsDomain {
            return .standard
        }
        return UserDefaults(suiteName: settingsDomain) ?? .standard
    }

    /// Steam's default install location for Skyrim SE on macOS.
    public static var defaultSteamInstallURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Steam/steamapps/common")
            .appending(path: "Skyrim Special Edition")
    }

    /// True inside a unit-test host. The host is the app bundle, so it inherits the
    /// developer's app settings and home directory.
    public static var isRunningInTestHost: Bool {
        let process = ProcessInfo.processInfo
        // Xcode sets the configuration path. `swift test` sets nothing, so its two
        // runner processes are recognised by name.
        return process.environment["XCTestConfigurationFilePath"] != nil
            || ["xctest", "swiftpm-testing-helper"].contains(process.processName)
    }

    /// Defaults `locate` consults for a persisted root, or nil when no source
    /// applies. A test host withholds it: the host shares the app's defaults
    /// domain, so a machine where the app has been pointed at a real install
    /// would feed that install to unit tests meant to be install-independent —
    /// which is how the unit tests came to block in `open()` on an external
    /// volume. Real-data suites gate on the environment variable instead.
    public static var persistedRootDefaults: UserDefaults? {
        isRunningInTestHost ? nil : settingsDefaults
    }

    /// Fallback install `locate` consults, or nil when no source applies.
    /// Withheld in a test host for the same reason as `persistedRootDefaults`:
    /// on a machine with a stock Steam library it is the developer's real
    /// install.
    public static var defaultInstallCandidate: URL? {
        isRunningInTestHost ? nil : defaultSteamInstallURL
    }

    /// Skyrim folders in the libraries Steam lists, withheld in a test host like
    /// `defaultInstallCandidate`.
    public static var steamLibraryCandidates: [URL] {
        isRunningInTestHost ? [] : SteamLibraryFolders.skyrimInstallCandidates()
    }

    /// Resolves and validates the game data root. Every source is injectable
    /// for tests; production callers use the defaults. A nil `userDefaults` or
    /// `defaultInstall` skips that source entirely.
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults? = persistedRootDefaults,
        defaultInstall: URL? = defaultInstallCandidate,
        steamLibraries: [URL] = steamLibraryCandidates,
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
        for library in steamLibraries {
            if let root = root(at: library, source: .steamLibrary, fileManager: fileManager) {
                return root
            }
        }
        let searched = ([defaultInstall].compactMap(\.self) + steamLibraries)
            .map { $0.path(percentEncoded: false) }
        throw GameDataError.notFound(searched: searched.reduce(into: []) { unique, path in
            if !unique.contains(path) {
                unique.append(path)
            }
        })
    }

    /// Persists a user-chosen install path (Settings UI). Validated first;
    /// an invalid choice throws and leaves the stored setting untouched.
    @discardableResult
    public static func saveUserChoice(
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
    public static func clearUserChoice(userDefaults: UserDefaults = settingsDefaults) {
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
