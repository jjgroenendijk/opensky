// File side of the save container. Saves live in Application Support, never the repo or
// the install. Writes go temp file, fsync, rename, so a crash keeps the old save; without
// the fsync, a power loss could leave a file of zeroes.

public import Foundation

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

    /// Writes `data` so `destination` holds its old contents or the new ones, never a mix.
    /// The temp file sits in a replacement folder on the same volume, because a rename is
    /// atomic only within one filesystem. `backups` older copies (`.bak`, `.bak.bak`, ...)
    /// rotate only after the new file is on disk.
    public static func writeAtomically(
        _ data: Data, to destination: URL, backups: Int = 0
    ) throws {
        let fileManager = FileManager.default
        let folder = try fileManager.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: destination.deletingLastPathComponent(), create: true
        )
        defer { try? fileManager.removeItem(at: folder) }
        let temporary = folder.appending(
            path: destination.lastPathComponent, directoryHint: .notDirectory
        )
        try write(data, to: temporary, fileManager: fileManager)
        try rotateBackups(of: destination, count: backups, fileManager: fileManager)
        try replace(destination, with: temporary)
    }

    /// The URL of the `generation`th backup of `file`: 0 is the file itself.
    public static func backup(of file: URL, generation: Int) -> URL {
        let name = file.lastPathComponent + String(repeating: ".bak", count: max(0, generation))
        return file.deletingLastPathComponent().appending(path: name, directoryHint: .notDirectory)
    }

    /// Moves each existing copy one generation older, dropping the oldest.
    private static func rotateBackups(
        of file: URL, count: Int, fileManager: FileManager
    ) throws {
        for generation in stride(from: count - 1, through: 0, by: -1) {
            let newer = backup(of: file, generation: generation)
            guard fileManager.fileExists(atPath: newer.path(percentEncoded: false)) else {
                continue
            }
            let older = backup(of: file, generation: generation + 1)
            if fileManager.fileExists(atPath: older.path(percentEncoded: false)) {
                try fileManager.removeItem(at: older)
            }
            try fileManager.moveItem(at: newer, to: older)
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
                unsafe rename(source, target) == 0
            }
        }
        guard moved else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
