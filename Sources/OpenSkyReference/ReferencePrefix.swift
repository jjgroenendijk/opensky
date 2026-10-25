// The folders and files inside the reference Wine prefix. Every write the tool makes,
// such as the console batch file and the ini edit, lands in here and never in the
// install OpenSky reads.

import Foundation

nonisolated public struct ReferencePrefix: Equatable, Sendable {
    public static let appID = "489830"
    public static let gameFolderName = "Skyrim Special Edition"
    public static let gameExecutableName = "SkyrimSE.exe"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var driveC: URL {
        root.appending(path: "drive_c", directoryHint: .isDirectory)
    }

    public var steamDirectory: URL {
        driveC.appending(path: "Program Files (x86)/Steam", directoryHint: .isDirectory)
    }

    public var steamExecutable: URL {
        steamDirectory.appending(path: "steam.exe")
    }

    /// Steam's browser helpers, one `cef.win*` folder each.
    public var cefDirectory: URL {
        steamDirectory.appending(path: "bin/cef", directoryHint: .isDirectory)
    }

    /// Exists once Steam has downloaded its client on the first start.
    public var steamUI: URL {
        steamDirectory.appending(path: "steamui.dll")
    }

    /// The private Wine, DXVK, GStreamer, and the Steam helpers that `reference/setup.sh`
    /// puts beside the prefix's own folders.
    public var runtimeDirectory: URL {
        root.appending(path: "opensky-runtime", directoryHint: .isDirectory)
    }

    public var wine: URL {
        runtimeDirectory.appending(path: "wine/bin/wine")
    }

    /// Unpacked rather than installed, so Wine finds it only through the launch environment.
    public var gstreamerDirectory: URL {
        runtimeDirectory.appending(path: "gstreamer", directoryHint: .isDirectory)
    }

    public var webHelperWrapper: URL {
        runtimeDirectory.appending(path: "steam-support/steamwebhelper-wrapper.exe")
    }

    public var steamApps: URL {
        steamDirectory.appending(path: "steamapps", directoryHint: .isDirectory)
    }

    public var gameDirectory: URL {
        steamApps.appending(path: "common/\(Self.gameFolderName)", directoryHint: .isDirectory)
    }

    public var gameExecutable: URL {
        gameDirectory.appending(path: Self.gameExecutableName)
    }

    public var appManifest: URL {
        steamApps.appending(path: "appmanifest_\(Self.appID).acf")
    }

    /// The Windows path Wine runs, because Wine resolves `C:` inside the prefix.
    public static let steamWindowsPath = #"C:\Program Files (x86)\Steam\steam.exe"#
    public static let gameWindowsPath =
        #"C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition\SkyrimSE.exe"#

    /// `My Games/Skyrim Special Edition` of the first Wine user, where the game keeps
    /// `SkyrimPrefs.ini` and `Saves/`.
    public func documentsDirectory(users: [String]) -> URL? {
        let user = users.sorted().first { $0 != "Public" && !$0.hasPrefix(".") }
        return user.map {
            driveC.appending(
                path: "users/\($0)/Documents/My Games/\(Self.gameFolderName)",
                directoryHint: .isDirectory
            )
        }
    }

    public func documentsDirectory() -> URL? {
        let users = driveC.appending(path: "users", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(
            atPath: users.path(percentEncoded: false)
        )) ?? []
        return documentsDirectory(users: names)
    }

    public func savesDirectory() -> URL? {
        documentsDirectory()?.appending(path: "Saves", directoryHint: .isDirectory)
    }

    public func prefsIni() -> URL? {
        documentsDirectory()?.appending(path: "SkyrimPrefs.ini")
    }

    /// `bat <name>` reads a file with no extension from the game folder
    /// (https://en.uesp.net/wiki/Skyrim:Console#Using_Batch_Files_with_the_bat_Command).
    public func batchFile(named name: String) -> URL {
        gameDirectory.appending(path: name)
    }
}

nonisolated public enum ReferencePrefixStatus: Equatable, Sendable {
    case notSet
    case missing(String)
    case noSteam(String)
    case noGame(String)
    case ready(String)

    public init(prefix: URL?, exists: (URL) -> Bool = {
        FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
    }) {
        guard let prefix else {
            self = .notSet
            return
        }
        let path = prefix.path(percentEncoded: false)
        let layout = ReferencePrefix(root: prefix)
        if !exists(layout.driveC) {
            self = .missing(path)
        } else if !exists(layout.steamExecutable) {
            self = .noSteam(path)
        } else if !exists(layout.gameExecutable) {
            self = .noGame(path)
        } else {
            self = .ready(path)
        }
    }

    public var isReady: Bool {
        if case .ready = self {
            true
        } else {
            false
        }
    }

    /// The line the settings page and `reference status` show.
    public var message: String {
        switch self {
        case .notSet: "No reference game prefix is set. Run make reference-setup."
        case let .missing(path): "The reference prefix has no drive_c: \(path)"
        case let .noSteam(path): "The reference prefix has no Windows Steam: \(path)"
        case let .noGame(path): "The reference prefix has no copy of the game: \(path)"
        case let .ready(path): "Reference game ready in \(path)"
        }
    }
}
