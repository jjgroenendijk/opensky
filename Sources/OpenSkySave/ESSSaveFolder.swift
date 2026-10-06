// The user's Skyrim saves folder: every `.ess` in it with its header and screenshot,
// read without decompressing a body. The folder is a setting, never a constant.
// See docs/engine/ess-import.md#the-saves-folder.

import Foundation
import OpenSkyFormatsESS
import OpenSkyGameData

/// One `.ess` file in the folder. `summary` is nil when the header cannot be read.
nonisolated public struct ESSSaveListing: Equatable, Sendable {
    public let url: URL
    public let modified: Date
    public let summary: ESSSummary?
    public let error: String?

    /// The file name without its extension, which the load list shows.
    public var name: String {
        url.deletingPathExtension().lastPathComponent
    }
}

nonisolated public enum ESSSaveFolderStatus: Equatable, Sendable {
    case notSet
    case missing(String)
    case empty(String)
    case ready(String, count: Int)

    /// The line the settings page shows.
    public var message: String {
        switch self {
        case .notSet: "No Skyrim saves folder is set."
        case let .missing(path): "The Skyrim saves folder does not exist: \(path)"
        case let .empty(path): "The Skyrim saves folder has no .ess files: \(path)"
        case let .ready(path, count): "\(count) Skyrim saves in \(path)"
        }
    }
}

nonisolated public struct ESSSaveFolder: Sendable {
    public static let fileExtension = "ess"
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func status(of directory: URL?) -> ESSSaveFolderStatus {
        guard let directory else { return .notSet }
        let path = directory.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return .missing(path) }
        let count = (try? ESSSaveFolder(directory: directory).saveURLs().count) ?? 0
        return count == 0 ? .empty(path) : .ready(path, count: count)
    }

    public func saveURLs() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == Self.fileExtension }
    }

    /// Every save, newest first. Reads only the header and screenshot of each.
    public func listings() throws -> [ESSSaveListing] {
        try saveURLs().map { url in
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            do {
                let summary = try ESSSummary(data: Data(contentsOf: url, options: .mappedIfSafe))
                return ESSSaveListing(url: url, modified: modified, summary: summary, error: nil)
            } catch {
                return ESSSaveListing(
                    url: url, modified: modified, summary: nil, error: String(describing: error)
                )
            }
        }
        .sorted { ($0.modified, $1.name) > ($1.modified, $0.name) }
    }

    @concurrent
    public func readListings() async throws -> [ESSSaveListing] {
        try listings()
    }

    @concurrent
    public static func readFile(at url: URL) async throws -> ESSFile {
        try ESSFile(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    // MARK: - List rows

    public static func summary(of header: ESSHeader) -> SaveSummary {
        SaveSummary(
            characterName: header.playerName, level: Int(header.playerLevel),
            raceName: header.playerRaceEditorID, locationName: header.playerLocation,
            playSeconds: 0
        )
    }

    /// The screenshot shrunk by whole steps to fit a save thumbnail.
    public static func thumbnail(of screenshot: ESSScreenshot) -> SaveThumbnail? {
        guard screenshot.width > 0, screenshot.height > 0 else { return nil }
        let largest = max(screenshot.width, screenshot.height)
        let step = (largest + SaveThumbnail.maximumSide - 1) / SaveThumbnail.maximumSide
        let width = screenshot.width / step
        let height = screenshot.height / step
        var rgba = Data(capacity: width * height * 4)
        let source = [UInt8](screenshot.rgba)
        for row in 0 ..< height {
            for column in 0 ..< width {
                let start = ((row * step) * screenshot.width + column * step) * 4
                guard start + 4 <= source.count else { return nil }
                rgba.append(contentsOf: source[start ..< start + 4])
            }
        }
        return SaveThumbnail(width: width, height: height, rgba: rgba)
    }
}

/// Where the Skyrim saves folder setting lives: the environment, else the shared
/// defaults domain the data root uses. There is no default path to probe.
nonisolated public enum ESSSaveFolderSetting {
    public static let environmentKey = "OPENSKY_SKYRIM_SAVES"
    public static let defaultsKey = "OpenSkySkyrimSavesFolder"

    public static func folder(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults? = GameDataLocator.persistedRootDefaults
    ) -> URL? {
        let path = environment[environmentKey].flatMap { $0.isEmpty ? nil : $0 }
            ?? userDefaults?.string(forKey: defaultsKey)
        guard let path, !path.isEmpty else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    public static func store(
        _ folder: URL,
        in defaults: UserDefaults = GameDataLocator.settingsDefaults
    ) {
        defaults.set(folder.path(percentEncoded: false), forKey: defaultsKey)
    }

    public static func clear(in defaults: UserDefaults = GameDataLocator.settingsDefaults) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
