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

/// One archive-provided resource path, as reported by enumeration.
nonisolated struct VFSEntry: Equatable {
    /// Canonical VFS key (lowercase, backslash separators).
    let path: String
    /// File name of the archive whose copy wins the lookup.
    let archive: String
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
        if looseFileURL(for: normalized) != nil {
            return true
        }
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

    /// Every path any archive provides, one entry per path attributed to the
    /// archive that wins the lookup, sorted by path for stable output. Loose
    /// files are not enumerated — walking all of Data/ costs more than a
    /// lookup layer should; `exists`/`contents` still prefer them. Opens
    /// (tables of) every archive; unreadable ones are skipped as usual.
    func archiveEntries() -> [VFSEntry] {
        var seen: Set<String> = []
        var result: [VFSEntry] = []
        // Slot 0 is the highest-priority archive, so first insert wins.
        for index in 0 ..< archiveCount {
            guard let archive = openedArchive(at: index) else { continue }
            let name = cache.withLock { $0.archives[index].url.lastPathComponent }
            for entry in archive.entries where seen.insert(entry.path).inserted {
                result.append(VFSEntry(path: entry.path, archive: name))
            }
        }
        return result.sorted { $0.path < $1.path }
    }

    /// Canonical VFS keys of files directly inside `directory` (one level, no
    /// recursion), from loose files and every archive combined. Loose and
    /// archive contributions union — either source makes the path resolvable via
    /// `contents(forPath:)`; a loose file still wins the actual read. For
    /// subsystems that must discover a known bounded directory (e.g.
    /// Interface/Translations) without walking all of `Data/`. Opens every
    /// archive, so callers use it sparingly. Sorted for stable output.
    func fileNames(inDirectory directory: String) -> [String] {
        guard let normalized = try? Self.normalize(directory) else { return [] }
        let prefix = normalized + "\\"
        var paths: Set<String> = []
        for name in looseFileNames(inDirectory: normalized) {
            paths.insert(prefix + name.lowercased())
        }
        for entry in archiveEntries() where entry.path.hasPrefix(prefix) {
            let remainder = entry.path.dropFirst(prefix.count)
            if !remainder.contains("\\") {
                paths.insert(entry.path)
            }
        }
        return paths.sorted()
    }

    /// On-disk names of regular files directly inside a loose directory (given
    /// as a normalized VFS key). Empty when the directory is absent. Resolves
    /// each path component case-insensitively, matching `looseFileURL`.
    private func looseFileNames(inDirectory normalized: String) -> [String] {
        var url = dataURL
        var directoryKey = ""
        for component in normalized.split(separator: "\\").map(String.init) {
            guard let onDisk = onDiskName(component, inDirectory: directoryKey, at: url) else {
                return []
            }
            url.append(path: onDisk, directoryHint: .isDirectory)
            directoryKey = directoryKey.isEmpty ? component : directoryKey + "\\" + component
        }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey]
        )) ?? []
        return contents.filter { entry in
            (try? entry.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }.map(\.lastPathComponent)
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
            if let archive = slot.archive {
                return archive
            }
            if slot.failedToOpen {
                return nil
            }
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
