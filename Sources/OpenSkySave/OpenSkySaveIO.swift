// File side of the save container. Saves live in Application Support, never the repo or
// the install. Writes go temp file, fsync, rename, so a crash keeps the old save; without
// the fsync, a power loss could leave a file of zeroes.

import Foundation

nonisolated public enum OpenSkySaveIO: Sendable {
    /// `~/Library/Application Support/OpenSky/Saves/`, created if absent.
    public static func defaultSavesDirectory(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appending(path: "OpenSky", directoryHint: .isDirectory)
            .appending(path: "Saves", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes `data` to `destination` so that the destination is either its
    /// old contents or the complete new ones, never a mixture.
    ///
    /// The temp file is created beside the destination, because a rename only
    /// replaces atomically within one filesystem. Any failure removes it, so a
    /// failed save leaves neither a damaged destination nor litter behind.
    public static func writeAtomically(_ data: Data, to destination: URL) throws {
        let fileManager = FileManager.default
        let directory = destination.deletingLastPathComponent()
        let temporary = directory.appending(
            path: ".\(destination.lastPathComponent).tmp-\(UUID().uuidString)",
            directoryHint: .notDirectory
        )
        do {
            try write(data, to: temporary, fileManager: fileManager)
            try replace(destination, with: temporary)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private static func write(_ data: Data, to url: URL, fileManager: FileManager) throws {
        guard fileManager.createFile(atPath: url.path(percentEncoded: false), contents: nil) else {
            throw CocoaError.error(.fileWriteNoPermission, userInfo: nil, url: url)
        }
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.write(contentsOf: data)
            // Contents on disk before the rename publishes the name.
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }

    private static func replace(_ destination: URL, with temporary: URL) throws {
        let moved = temporary.path(percentEncoded: false).withCString { source in
            destination.path(percentEncoded: false).withCString { target in
                rename(source, target) == 0
            }
        }
        guard moved else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
