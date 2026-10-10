// Where the cache may live, and what to warn about before a build. The cache holds
// content derived from the user's install, so it must never sit inside the game
// install or inside a git checkout, where it could be committed.

import Foundation

nonisolated public enum AssetCacheLocationError: Error, Equatable, Sendable {
    case insideGameInstall
    case insideRepository(URL)
    case containsGameInstall
}

/// Facts about the disk that holds a folder. The shell reads them; the rules are pure.
nonisolated public struct AssetCacheVolume: Equatable, Sendable {
    public let isInternal: Bool
    public let isLocal: Bool
    public let availableBytes: UInt64

    public init(isInternal: Bool, isLocal: Bool, availableBytes: UInt64) {
        self.isInternal = isInternal
        self.isLocal = isLocal
        self.availableBytes = availableBytes
    }

    /// Reads the facts of the volume that holds `url`, or of its nearest existing parent.
    public static func of(_ url: URL) -> Self? {
        let parts = url.standardizedFileURL.pathComponents
        let existing = stride(from: parts.count, through: 1, by: -1).lazy
            .map { AssetCacheLocation.folderURL(parts.prefix($0)) }
            .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
        guard let probe = existing else { return nil }
        let keys: Set<URLResourceKey> = [
            .volumeIsInternalKey, .volumeIsLocalKey, .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? probe.resourceValues(forKeys: keys) else { return nil }
        return Self(
            isInternal: values.volumeIsInternal ?? false,
            isLocal: values.volumeIsLocal ?? true,
            availableBytes: UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0))
        )
    }
}

nonisolated public enum AssetCacheLocationWarning: Equatable, Sendable {
    /// Reads from an external disk may be slower than from the internal SSD.
    case externalDisk
    /// Reads over the network are slower still, and the share may go away.
    case networkDisk
    /// The disk has less free space than the cache needs.
    case lowFreeSpace(availableBytes: UInt64, neededBytes: UInt64)

    public var isLowFreeSpace: Bool {
        if case .lowFreeSpace = self {
            true
        } else {
            false
        }
    }
}

nonisolated public enum AssetCacheLocation {
    /// `~/Library/Caches/OpenSky/AssetCache`, on the internal disk.
    public static func defaultFolder() throws -> URL {
        try FileManager.default
            .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "OpenSky", directoryHint: .isDirectory)
            .appending(path: "AssetCache", directoryHint: .isDirectory)
    }

    /// Refuses a folder inside the game install, around it, or inside a git checkout.
    public static func validate(_ folder: URL, gameInstall: URL?) throws {
        let candidate = components(of: folder)
        if let gameInstall {
            let install = components(of: gameInstall)
            if candidate.starts(with: install) {
                throw AssetCacheLocationError.insideGameInstall
            }
            if install.starts(with: candidate) {
                throw AssetCacheLocationError.containsGameInstall
            }
        }
        if let repository = enclosingRepository(of: folder) {
            throw AssetCacheLocationError.insideRepository(repository)
        }
    }

    /// The warnings to show before a build that needs `neededBytes` more on disk.
    public static func warnings(
        volume: AssetCacheVolume, neededBytes: UInt64
    ) -> [AssetCacheLocationWarning] {
        var warnings: [AssetCacheLocationWarning] = []
        if !volume.isLocal {
            warnings.append(.networkDisk)
        } else if !volume.isInternal {
            warnings.append(.externalDisk)
        }
        if volume.availableBytes < neededBytes {
            warnings.append(.lowFreeSpace(
                availableBytes: volume.availableBytes,
                neededBytes: neededBytes
            ))
        }
        return warnings
    }

    /// The nearest folder at or above `folder` that holds a `.git` entry.
    static func enclosingRepository(of folder: URL) -> URL? {
        let parts = folder.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let candidates = stride(from: parts.count, through: 1, by: -1).lazy
            .map { folderURL(parts.prefix($0)) }
        return candidates.first { candidate in
            FileManager.default
                .fileExists(atPath: candidate.appending(path: ".git").path(percentEncoded: false))
        }
    }

    static func folderURL(_ parts: ArraySlice<String>) -> URL {
        URL(filePath: NSString.path(withComponents: Array(parts)), directoryHint: .isDirectory)
    }

    private static func components(of url: URL) -> [String] {
        url.standardizedFileURL.resolvingSymlinksInPath().pathComponents.map { $0.lowercased() }
    }
}

nonisolated extension AssetCacheLocationWarning {
    public var message: String {
        switch self {
        case .externalDisk:
            "The folder is on an external disk, which may read slower than the internal disk."
        case .networkDisk:
            "The folder is on a network disk. Reads are slow, and the disk may go away."
        case let .lowFreeSpace(available, needed):
            "The disk has \(available.formatted(.byteCount(style: .file))) free, but the "
                + "conversion needs about \(needed.formatted(.byteCount(style: .file))). "
                + "Free space or choose another folder."
        }
    }
}

nonisolated extension AssetCacheStore {
    /// The warnings for this store's folder before a build that writes `neededBytes`.
    public func locationWarnings(neededBytes: UInt64) -> [AssetCacheLocationWarning] {
        guard let volume = AssetCacheVolume.of(root) else { return [] }
        let stored = usage().bytes
        return AssetCacheLocation.warnings(
            volume: volume,
            neededBytes: neededBytes - min(neededBytes, stored)
        )
    }
}
