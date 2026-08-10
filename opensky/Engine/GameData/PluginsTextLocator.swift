// Finds the `plugins.txt` that carries the user's plugin load order (issue #73).
//
// The game writes this file into its Windows per-user application data folder,
// which on this platform only exists inside whatever compatibility layer runs
// the game — a Steam Proton prefix, a Wine prefix, a CrossOver or Whisky
// bottle. There is no single correct path, so the locator searches the layouts
// that exist in practice and lets the user name the file outright when theirs
// is somewhere else.
//
// Resolution order (first configured source wins):
//   1. OPENSKY_PLUGINS_TXT environment variable (tests, CLI runs)
//   2. UserDefaults key "OpenSkyPluginsText" (Settings)
//   3. The first candidate layout that exists on disk
//
// Nothing here fails the load: a missing plugins.txt is an ordinary state that
// resolves to the vanilla masters (see `PluginLoadOrder`). An explicitly
// configured path that does not exist is reported rather than ignored, so the
// Settings window can say so instead of silently loading a different order.
//
// Format and layout notes: docs/formats/plugins-txt.md.

import Foundation

/// Where a `plugins.txt` came from. The Settings window turns this into the
/// note under the path.
nonisolated enum PluginsTextSource: Equatable {
    case environment
    case userDefaults
    /// Next to the game executable — how a portable or hand-managed install is
    /// usually laid out on this platform.
    case installFolder
    /// `~/Library/Application Support/Skyrim Special Edition/`.
    case applicationSupport
    /// Inside a Windows compatibility prefix (Proton, Wine, CrossOver, Whisky).
    case windowsPrefix
}

/// The outcome of looking for a `plugins.txt`.
nonisolated enum PluginsTextLocation: Equatable {
    case located(url: URL, source: PluginsTextSource)
    /// An override names a file that is not readable. Never falls through to
    /// another source: a configured path that is wrong is a mistake to report.
    case overrideMissing(path: String, source: PluginsTextSource)
    /// No override and no candidate layout holds one.
    case notFound(searched: [String])

    var url: URL? {
        if case let .located(url, _) = self {
            return url
        }
        return nil
    }

    var problemDescription: String? {
        switch self {
        case .located:
            nil
        case let .overrideMissing(path, source):
            "Configured plugins.txt (\(PluginsTextLocator.originName(of: source))) "
                + "cannot be read: \(path)."
        case .notFound:
            "No plugins.txt found. Loading the vanilla masters only; "
                + "choose the file in Settings to use a real load order."
        }
    }
}

nonisolated enum PluginsTextLocator {
    static let environmentKey = "OPENSKY_PLUGINS_TXT"
    static let defaultsKey = "OpenSkyPluginsText"

    /// The game's folder name under a Windows `AppData/Local`, and under
    /// `~/Library/Application Support` where this app looks natively.
    static let gameFolderName = "Skyrim Special Edition"

    /// Steam application id for Skyrim Special Edition, used to find the
    /// Proton compatibility prefix beside the install.
    static let steamAppID = "489830"

    /// Defaults store holding the setting: the same shared domain as the data
    /// root, so app and CLI agree.
    static var settingsDefaults: UserDefaults {
        GameDataLocator.settingsDefaults
    }

    /// Defaults `locate` consults, or nil when no source applies. Withheld in a
    /// test host for the reason `GameDataLocator.persistedRootDefaults`
    /// documents: the host shares the app's defaults domain, and a unit test
    /// must not pick up the developer's own load order.
    static var persistedDefaults: UserDefaults? {
        GameDataLocator.isRunningInTestHost ? nil : settingsDefaults
    }

    /// Home directory the candidate search walks, or nil when no source
    /// applies. Withheld in a test host for the same reason.
    static var homeCandidate: URL? {
        GameDataLocator.isRunningInTestHost
            ? nil
            : FileManager.default.homeDirectoryForCurrentUser
    }

    /// Resolves the `plugins.txt` for one install. Every source is injectable;
    /// production callers use the defaults. A nil `userDefaults` or `home`
    /// skips that source entirely.
    static func locate(
        root: GameDataRoot,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults? = persistedDefaults,
        home: URL? = homeCandidate,
        fileManager: FileManager = .default
    ) -> PluginsTextLocation {
        if let path = environment[environmentKey], !path.isEmpty {
            return override(path: path, source: .environment, fileManager: fileManager)
        }
        if let path = userDefaults?.string(forKey: defaultsKey), !path.isEmpty {
            return override(path: path, source: .userDefaults, fileManager: fileManager)
        }
        let candidates = candidates(root: root, home: home, fileManager: fileManager)
        for candidate in candidates where isReadable(candidate.url, fileManager: fileManager) {
            return .located(url: candidate.url, source: candidate.source)
        }
        return .notFound(searched: candidates.map { $0.url.path(percentEncoded: false) })
    }

    /// Every layout the search considers, in priority order. Exposed so the
    /// Settings window can list what was looked at when nothing was found.
    static func candidates(
        root: GameDataRoot,
        home: URL? = homeCandidate,
        fileManager: FileManager = .default
    ) -> [(source: PluginsTextSource, url: URL)] {
        var found: [(source: PluginsTextSource, url: URL)] = [
            (
                .installFolder,
                root.installURL.appending(path: "plugins.txt", directoryHint: .notDirectory)
            )
        ]
        if let home {
            found.append((
                .applicationSupport,
                home.appending(path: "Library/Application Support")
                    .appending(path: gameFolderName)
                    .appending(path: "plugins.txt", directoryHint: .notDirectory)
            ))
        }
        for prefix in windowsPrefixes(root: root, home: home, fileManager: fileManager) {
            for user in prefixUserFolders(prefix, fileManager: fileManager) {
                found.append((
                    .windowsPrefix,
                    user.appending(path: "AppData/Local")
                        .appending(path: gameFolderName)
                        .appending(path: "plugins.txt", directoryHint: .notDirectory)
                ))
            }
        }
        return found
    }

    /// Persists a user-chosen path (Settings UI). Checked first; an unreadable
    /// choice throws and leaves the stored setting untouched.
    @discardableResult
    static func saveUserChoice(
        path: String,
        userDefaults: UserDefaults = settingsDefaults,
        fileManager: FileManager = .default
    ) throws -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        let url = URL(filePath: expanded, directoryHint: .notDirectory)
        guard isReadable(url, fileManager: fileManager) else {
            throw PluginsTextError.unreadable(path: path)
        }
        userDefaults.set(expanded, forKey: defaultsKey)
        return url
    }

    /// Removes the persisted choice; the next locate searches again.
    static func clearUserChoice(userDefaults: UserDefaults = settingsDefaults) {
        userDefaults.removeObject(forKey: defaultsKey)
    }

    /// Human-readable name of a source, for Settings notes and error text.
    static func originName(of source: PluginsTextSource) -> String {
        switch source {
        case .environment: "environment variable \(environmentKey)"
        case .userDefaults: "chosen in Settings"
        case .installFolder: "install folder"
        case .applicationSupport: "~/Library/Application Support/\(gameFolderName)"
        case .windowsPrefix: "Windows compatibility prefix"
        }
    }

    // MARK: - Candidate layouts

    /// Roots of Windows compatibility prefixes that might hold the game's
    /// per-user data. Each is a folder containing `drive_c`. These are the
    /// stock locations of the tools people run Windows games with on macOS;
    /// a non-stock layout is what the Settings override is for.
    private static func windowsPrefixes(
        root: GameDataRoot,
        home: URL?,
        fileManager: FileManager
    ) -> [URL] {
        // <library>/steamapps/common/<game>/ -> <library>/steamapps/compatdata/<id>/pfx
        var prefixes = [
            root.installURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "compatdata")
                .appending(path: steamAppID)
                .appending(path: "pfx", directoryHint: .isDirectory)
        ]
        guard let home else { return prefixes }
        prefixes.append(home.appending(path: ".wine", directoryHint: .isDirectory))
        let bottleHomes = [
            home.appending(path: "Library/Application Support/CrossOver/Bottles"),
            home.appending(path: "Library/Containers/com.isaacmarovitz.Whisky/Bottles")
        ]
        for bottleHome in bottleHomes {
            let names = (try? fileManager.contentsOfDirectory(
                atPath: bottleHome.path(percentEncoded: false)
            )) ?? []
            prefixes.append(contentsOf: names.sorted().map {
                bottleHome.appending(path: $0, directoryHint: .isDirectory)
            })
        }
        return prefixes
    }

    /// `drive_c/users/<name>` folders inside one prefix, skipping the shared
    /// `Public` profile which never holds the game's settings.
    private static func prefixUserFolders(
        _ prefix: URL,
        fileManager: FileManager
    ) -> [URL] {
        let users = prefix.appending(path: "drive_c/users", directoryHint: .isDirectory)
        let names = (try? fileManager.contentsOfDirectory(
            atPath: users.path(percentEncoded: false)
        )) ?? []
        return names
            .filter { $0.caseInsensitiveCompare("Public") != .orderedSame && !$0.hasPrefix(".") }
            .sorted()
            .map { users.appending(path: $0, directoryHint: .isDirectory) }
    }

    // MARK: - Helpers

    private static func override(
        path: String,
        source: PluginsTextSource,
        fileManager: FileManager
    ) -> PluginsTextLocation {
        let expanded = NSString(string: path).expandingTildeInPath
        let url = URL(filePath: expanded, directoryHint: .notDirectory)
        guard isReadable(url, fileManager: fileManager) else {
            return .overrideMissing(path: expanded, source: source)
        }
        return .located(url: url, source: source)
    }

    private static func isReadable(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && !isDirectory.boolValue
    }
}

nonisolated enum PluginsTextError: Error, Equatable {
    case unreadable(path: String)
}

nonisolated extension PluginsTextError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .unreadable(path):
            "Cannot read a plugins.txt at \(path)."
        }
    }
}
