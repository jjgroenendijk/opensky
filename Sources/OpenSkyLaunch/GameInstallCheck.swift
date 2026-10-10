// What the launcher found in the game folder: the build, the DLC, the counts,
// and what is wrong with it. It reads file names and headers only, so it takes
// well under a second. The launcher, the sidebar, and openskycli read this value.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct GameInstallProblem: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case missingMaster
        case unreadableArchive
        case unreadablePlugin
        case unreadableFolder
    }

    public let kind: Kind
    /// The file or folder the problem is about.
    public let subject: String
    public let message: String
    /// One line that says how to fix it.
    public let fix: String

    public init(kind: Kind, subject: String, message: String, fix: String) {
        self.kind = kind
        self.subject = subject
        self.message = message
        self.fix = fix
    }
}

nonisolated public enum OfficialDLC: String, CaseIterable, Sendable {
    case dawnguard = "Dawnguard.esm"
    case hearthfires = "HearthFires.esm"
    case dragonborn = "Dragonborn.esm"

    public var title: String {
        switch self {
        case .dawnguard: "Dawnguard"
        case .hearthfires: "Hearthfire"
        case .dragonborn: "Dragonborn"
        }
    }
}

nonisolated public struct GameInstallSummary: Equatable, Sendable {
    public var gameVersion: PEFileVersion?
    public var dlc: [OfficialDLC] = []
    public var creationClubPlugins = 0
    public var archives = 0
    public var plugins = 0
    /// The `HEDR` record counts of every plugin that was read, added up.
    public var records = 0
    public var problems: [GameInstallProblem] = []

    public init() {}

    public var isComplete: Bool {
        problems.isEmpty
    }

    /// `Version 1.6.1170.0, 3 of 3 DLC, 4 Creation Club plugins`.
    public var headline: String {
        let version = gameVersion.map { "Version \($0)" } ?? "Version unknown"
        return "\(version), \(dlc.count) of \(OfficialDLC.allCases.count) DLC, "
            + "\(creationClubPlugins) Creation Club plugins"
    }

    /// Plugins that are neither the base game, an official DLC, nor Creation Club.
    public var modPlugins: Int {
        let missing = problems.filter { $0.kind == .missingMaster }.count
        let base = GameInstallCheck.requiredMasters.count - missing
        return max(0, plugins - base - dlc.count - creationClubPlugins)
    }

    /// `26 archives, 10 plugins, 1,029,317 records`.
    public var countLine: String {
        "\(archives) archives, \(plugins) plugins, "
            + "\(records.formatted(.number.grouping(.automatic))) records"
    }

    /// `Update.esm is missing. Verify the game files in Steam, then check again.`
    public var problemLines: [String] {
        problems.map { "\($0.message). \($0.fix)." }
    }
}

nonisolated public enum GameInstallCheck {
    public static let requiredMasters = ["Skyrim.esm", "Update.esm"]
    static let executableName = "SkyrimSE.exe"
    private static let pluginExtensions: Set = ["esm", "esp", "esl"]

    /// Runs off the main actor: it reads a header of every plugin and archive.
    @concurrent
    public static func check(installURL: URL) async -> GameInstallSummary {
        run(installURL: installURL)
    }

    /// `installURL` is the folder that holds `Data/`.
    public static func run(
        installURL: URL, fileManager: FileManager = .default
    ) -> GameInstallSummary {
        var summary = GameInstallSummary()
        let dataURL = installURL.appending(path: "Data", directoryHint: .isDirectory)
        guard let names = try? fileManager.contentsOfDirectory(atPath: dataURL.path) else {
            summary.problems.append(unreadableFolder(dataURL, fileManager: fileManager))
            return summary
        }
        summary.gameVersion = try? PEVersionInfo.fileVersion(
            url: installURL.appending(path: executableName)
        )
        let lowered = Dictionary(names.map { ($0.lowercased(), $0) }) { first, _ in first }
        for master in requiredMasters where lowered[master.lowercased()] == nil {
            summary.problems.append(GameInstallProblem(
                kind: .missingMaster, subject: master, message: "\(master) is missing",
                fix: "Verify the game files in Steam, then check again"
            ))
        }
        summary.dlc = OfficialDLC.allCases.filter { lowered[$0.rawValue.lowercased()] != nil }
        for name in names.sorted() {
            let url = dataURL.appending(path: name)
            switch (name as NSString).pathExtension.lowercased() {
            case "bsa":
                summary.archives += 1
                checkArchive(url, name: name, into: &summary)
            case let ext where pluginExtensions.contains(ext):
                summary.plugins += 1
                if name.lowercased().hasPrefix("cc") {
                    summary.creationClubPlugins += 1
                }
                checkPlugin(url, name: name, into: &summary)
            default:
                continue
            }
        }
        return summary
    }

    private static func checkArchive(
        _ url: URL,
        name: String,
        into summary: inout GameInstallSummary
    ) {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try BSAArchive.validateHeader(handle.read(upToCount: BSAArchive.headerSize) ?? Data())
        } catch {
            summary.problems.append(GameInstallProblem(
                kind: .unreadableArchive, subject: name, message: "\(name) cannot be read",
                fix: "Verify the game files in Steam to replace it"
            ))
        }
    }

    private static func checkPlugin(
        _ url: URL,
        name: String,
        into summary: inout GameInstallSummary
    ) {
        do {
            let header = try PluginHeader(pluginData: Data(contentsOf: url, options: .alwaysMapped))
            summary.records += Int(max(0, header.stats.recordCount))
        } catch {
            summary.problems.append(GameInstallProblem(
                kind: .unreadablePlugin, subject: name, message: "\(name) cannot be read",
                fix: "Verify the game files in Steam, or remove the plugin"
            ))
        }
    }

    private static func unreadableFolder(
        _ url: URL,
        fileManager: FileManager
    ) -> GameInstallProblem {
        let path = url.path(percentEncoded: false)
        let exists = fileManager.fileExists(atPath: path)
        return GameInstallProblem(
            kind: .unreadableFolder, subject: path,
            message: exists ? "The Data folder cannot be read" : "The folder has no Data folder",
            fix: exists
                ? "Allow OpenSky in System Settings > Privacy & Security > Files and Folders"
                : "Choose the folder that holds Data/Skyrim.esm"
        )
    }
}
