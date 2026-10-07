// One lookup layer over the data root: loose files under `Data/` first, then
// archives, last opened wins. Keys ignore case and separator. Archives open lazily; a
// malformed one is logged and skipped. See docs/formats/vfs.md.

import Foundation
import OpenSkyFormatsCore
import Synchronization

nonisolated public enum VFSError: Error, Equatable, Sendable {
    /// Empty path or one that escapes the data root — never valid game data.
    case invalidPath(String)
    case fileNotFound(path: String)
}

/// One archive-provided resource path, as reported by enumeration.
nonisolated public struct VFSEntry: Equatable, Sendable {
    /// Canonical VFS key (lowercase, backslash separators).
    public let path: String
    /// File name of the archive whose copy wins the lookup.
    public let archive: String

    public init(path: String, archive: String) {
        self.path = path
        self.archive = archive
    }
}

nonisolated public final class VirtualFileSystem: GameFileSource {
    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "VFS"
    )

    private struct ArchiveSlot {
        let url: URL
        var archive: BSAArchive?
        var failedToOpen = false
        var modified: Int64?
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
    public let archiveCount: Int

    /// - Parameter archiveURLs: archives in open order — first is opened
    ///   first and has the lowest priority; later archives override earlier
    ///   ones on conflicting paths.
    public init(dataURL: URL, archiveURLs: [URL]) {
        self.dataURL = dataURL
        archiveCount = archiveURLs.count
        cache = Mutex(Cache(archives: archiveURLs.reversed().map {
            ArchiveSlot(url: $0)
        }))
    }

    /// Opens every archive the install's plugin load order implies. Archive
    /// priority follows plugin priority, so a mod's archive overrides the
    /// archives of every plugin loaded before it (docs/formats/vfs.md).
    public convenience init(root: GameDataRoot) {
        self.init(
            dataURL: root.dataURL,
            archiveURLs: ArchiveLoadOrder.resolve(
                installURL: root.installURL,
                dataURL: root.dataURL,
                pluginOrder: PluginLoadOrder.resolve(root: root).entries.map(\.name)
            )
        )
    }

    /// True when the path resolves to a loose file or an archive entry.
    public func exists(_ path: String) -> Bool {
        guard let normalized = try? Self.normalize(path) else { return false }
        if looseFileURL(for: normalized) != nil {
            return true
        }
        return archiveEntry(for: normalized) != nil
    }

    /// Loads one resource's bytes. Loose file wins over any archive.
    public func contents(forPath path: String) throws -> Data {
        let normalized = try Self.normalize(path)
        if let url = looseFileURL(for: normalized) {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        }
        if let (archive, entry) = archiveEntry(for: normalized) {
            return try archive.contents(of: entry)
        }
        throw VFSError.fileNotFound(path: normalized)
    }

    /// A loose file reports its own size and time; an archive entry reports its
    /// stored size and the archive's time.
    public func provenance(forPath path: String) -> GameFileProvenance? {
        guard let normalized = try? Self.normalize(path) else { return nil }
        if let url = looseFileURL(for: normalized) {
            let values = try? url.resourceValues(forKeys: [
                .fileSizeKey,
                .contentModificationDateKey
            ])
            return GameFileProvenance(
                origin: GameFileProvenance.looseOrigin,
                size: UInt64(values?.fileSize ?? 0),
                modified: Int64(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
            )
        }
        for index in 0 ..< archiveCount {
            guard
                let archive = openedArchive(at: index),
                let entry = archive.entry(forNormalizedPath: normalized)
            else { continue }
            let (name, modified) = archiveStamp(at: index)
            return GameFileProvenance(
                origin: name,
                size: UInt64(entry.packedSize),
                modified: modified
            )
        }
        return nil
    }

    /// Every path any archive provides, one entry per path attributed to the
    /// archive that wins the lookup, sorted by path for stable output. Loose
    /// files are not enumerated — walking all of Data/ costs more than a
    /// lookup layer should; `exists`/`contents` still prefer them. Opens
    /// (tables of) every archive; unreadable ones are skipped as usual.
    public func archiveEntries() -> [VFSEntry] {
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

    /// Sorted VFS keys of files directly inside `directory`, from loose files and all
    /// archives. Opens every archive, so use it only for small known folders such as
    /// Interface/Translations.
    public func fileNames(inDirectory directory: String) -> [String] {
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
    public static func normalize(_ path: String) throws -> String {
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
            if let entry = archive.entry(forNormalizedPath: normalized) {
                return (archive, entry)
            }
        }
        return nil
    }

    private func archiveStamp(at index: Int) -> (name: String, modified: Int64) {
        cache.withLock { cache in
            let slot = cache.archives[index]
            if let modified = slot.modified {
                return (slot.url.lastPathComponent, modified)
            }
            let date = try? slot.url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            let modified = Int64(date?.timeIntervalSince1970 ?? 0)
            cache.archives[index].modified = modified
            return (slot.url.lastPathComponent, modified)
        }
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
