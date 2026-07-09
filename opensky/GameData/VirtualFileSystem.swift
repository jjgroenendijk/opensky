// One lookup layer over the game data root. Per-lookup resolution order:
//   1. Loose files under `Data/` (modding convention: loose overrides archives)
//   2. Archives, last-opened wins (plugin archives override base archives)
//
// Keys are case-insensitive and separator-insensitive ("/" == "\") because
// records reference resources with inconsistent casing and separators.
// Archives open lazily on first lookup; a malformed archive is logged and
// skipped, never fatal (mod-quirk rule, AGENTS.md). Full rules + references:
// docs/formats/vfs.md.

import Foundation
import OSLog
import Synchronization

nonisolated enum VFSError: Error, Equatable {
    /// Empty path or one that escapes the data root — never valid game data.
    case invalidPath(String)
    case fileNotFound(path: String)
}

nonisolated final class VirtualFileSystem: Sendable {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "VFS"
    )

    private struct ArchiveSlot {
        let url: URL
        var archive: BSAArchive?
        var failedToOpen = false
    }

    private struct Cache {
        /// Slots in lookup order: highest priority (opened last) first.
        var archives: [ArchiveSlot]
        /// Loose-file listings: normalized directory path ("" = data root) ->
        /// lowercased entry name -> on-disk name. Built lazily per directory;
        /// never invalidated — files added while running are not seen.
        var directories: [String: [String: String]] = [:]
    }

    private let dataURL: URL
    private let cache: Mutex<Cache>
    let archiveCount: Int

    /// - Parameter archiveURLs: archives in open order — first is opened
    ///   first and has the lowest priority; later archives override earlier
    ///   ones on conflicting paths.
    init(dataURL: URL, archiveURLs: [URL]) {
        self.dataURL = dataURL
        archiveCount = archiveURLs.count
        cache = Mutex(Cache(archives: archiveURLs.reversed().map {
            ArchiveSlot(url: $0)
        }))
    }

    convenience init(root: GameDataRoot) {
        self.init(
            dataURL: root.dataURL,
            archiveURLs: ArchiveLoadOrder.resolve(
                installURL: root.installURL,
                dataURL: root.dataURL
            )
        )
    }

    /// True when the path resolves to a loose file or an archive entry.
    func exists(_ path: String) -> Bool {
        guard let normalized = try? Self.normalize(path) else { return false }
        if looseFileURL(for: normalized) != nil { return true }
        return archiveEntry(for: normalized) != nil
    }

    /// Loads one resource's bytes. Loose file wins over any archive.
    func contents(forPath path: String) throws -> Data {
        let normalized = try Self.normalize(path)
        if let url = looseFileURL(for: normalized) {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        }
        if let (archive, entry) = archiveEntry(for: normalized) {
            return try archive.contents(of: entry)
        }
        throw VFSError.fileNotFound(path: normalized)
    }

    /// Canonical key: lowercase, backslash separators, no redundant
    /// separators. Rejects empty paths and "."/".." components — game data
    /// never uses them, and they could escape the data root.
    static func normalize(_ path: String) throws -> String {
        let components = path.lowercased()
            .replacingOccurrences(of: "/", with: "\\")
            .split(separator: "\\")
        guard !components.isEmpty else { throw VFSError.invalidPath(path) }
        guard !components.contains(where: { $0 == "." || $0 == ".." }) else {
            throw VFSError.invalidPath(path)
        }
        return components.joined(separator: "\\")
    }

    // MARK: - Loose files

    private func looseFileURL(for normalized: String) -> URL? {
        let components = normalized.split(separator: "\\").map(String.init)
        var url = dataURL
        var directoryKey = ""
        for (index, component) in components.enumerated() {
            guard let onDisk = onDiskName(component, inDirectory: directoryKey, at: url) else {
                return nil
            }
            let isLast = index == components.count - 1
            url.append(path: onDisk, directoryHint: isLast ? .notDirectory : .isDirectory)
            directoryKey = directoryKey.isEmpty ? component : directoryKey + "\\" + component
        }
        return url
    }

    /// Case-insensitive component match via a lazily built directory listing,
    /// so lookups also work on case-sensitive volumes where a direct stat
    /// would miss. Case-duplicate names on such volumes resolve arbitrarily.
    private func onDiskName(
        _ lowercasedName: String,
        inDirectory key: String,
        at url: URL
    ) -> String? {
        cache.withLock { cache in
            if let listing = cache.directories[key] {
                return listing[lowercasedName]
            }
            let names = (try? FileManager.default.contentsOfDirectory(
                atPath: url.path(percentEncoded: false)
            )) ?? []
            var listing: [String: String] = [:]
            listing.reserveCapacity(names.count)
            for name in names {
                listing[name.lowercased()] = name
            }
            cache.directories[key] = listing
            return listing[lowercasedName]
        }
    }

    // MARK: - Archives

    private func archiveEntry(for normalized: String) -> (BSAArchive, BSAArchive.Entry)? {
        for index in 0 ..< archiveCount {
            guard let archive = openedArchive(at: index) else { continue }
            if let entry = archive.entry(forPath: normalized) {
                return (archive, entry)
            }
        }
        return nil
    }

    /// Opens (parses tables of) the archive on first use. A failed open is
    /// logged once and the slot skipped from then on.
    private func openedArchive(at index: Int) -> BSAArchive? {
        cache.withLock { cache in
            let slot = cache.archives[index]
            if let archive = slot.archive { return archive }
            if slot.failedToOpen { return nil }
            do {
                let archive = try BSAArchive(url: slot.url)
                cache.archives[index].archive = archive
                return archive
            } catch {
                cache.archives[index].failedToOpen = true
                let name = slot.url.lastPathComponent
                Self.logger.error(
                    """
                    Skipping unreadable archive \(name, privacy: .public): \
                    \(String(describing: error), privacy: .public)
                    """
                )
                return nil
            }
        }
    }
}
