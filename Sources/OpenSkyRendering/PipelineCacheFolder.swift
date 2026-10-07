// Where the pipeline archive lives, and its name. A compiled binary is only valid for
// one OS build, one GPU, one shader library, and one app binary, so the name holds
// all four. An archive with another name is stale and is deleted on save.

import CryptoKit
import Foundation
import Metal

nonisolated public enum PipelineCacheFolder {
    /// The archive folder inside the asset cache folder.
    public static func folder(inCacheFolder cacheFolder: URL) -> URL {
        cacheFolder.appending(path: "pipelines", directoryHint: .isDirectory)
    }

    /// The archive for this process, or nil when the shader library or the executable
    /// cannot be found, so nothing identifies the build.
    public static func archiveURL(inCacheFolder cacheFolder: URL, device: MTLDevice) -> URL? {
        guard
            let library = Bundle.main.url(forResource: "default", withExtension: "metallib"),
            let executable = Bundle.main.executableURL,
            let libraryStamp = fileStamp(library),
            let executableStamp = fileStamp(executable)
        else { return nil }
        let name = archiveName(
            osBuild: ProcessInfo.processInfo.operatingSystemVersionString,
            gpu: device.name,
            stamps: [libraryStamp, executableStamp]
        )
        return folder(inCacheFolder: cacheFolder).appending(path: name)
    }

    /// FNV-1a over the parts, so any change gives another name.
    static func archiveName(osBuild: String, gpu: String, stamps: [String]) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in ([osBuild, gpu] + stamps).joined(separator: "\u{0}").utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return String(format: "%016llx.mtl4archive", hash)
    }

    private static func fileStamp(_ url: URL) -> String? {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard
            let values = try? url.resourceValues(forKeys: keys),
            let size = values.fileSize,
            let date = values.contentModificationDate
        else { return nil }
        return "\(size)-\(date.timeIntervalSince1970)"
    }

    /// The SHA-256 of the archive, written beside it after a save.
    static func checksumURL(for fileURL: URL) -> URL {
        fileURL.appendingPathExtension("sha256")
    }

    static func writeChecksum(for fileURL: URL) throws {
        let digest = try SHA256.hash(data: Data(contentsOf: fileURL, options: .mappedIfSafe))
        try Data(digest).write(to: checksumURL(for: fileURL), options: .atomic)
    }

    /// True when the archive matches the checksum written when it was saved.
    static func isIntact(_ fileURL: URL) -> Bool {
        guard
            let expected = try? Data(contentsOf: checksumURL(for: fileURL)),
            let archive = try? Data(contentsOf: fileURL, options: .mappedIfSafe)
        else { return false }
        return Data(SHA256.hash(data: archive)) == expected
    }

    /// Deletes the archive and its checksum.
    static func remove(_ fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: checksumURL(for: fileURL))
    }

    /// Makes the folder and deletes every other archive in it.
    static func prepare(for fileURL: URL) throws {
        let folder = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try clear(folder: folder, keeping: fileURL.lastPathComponent)
    }

    /// Deletes the archives in `folder`, except `keeping`. Returns how many it deleted.
    @discardableResult
    public static func clear(folder: URL, keeping: String? = nil) throws -> Int {
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else {
            return 0
        }
        let stale = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "mtl4archive" && $0.lastPathComponent != keeping }
        for url in stale {
            try FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: checksumURL(for: url))
        }
        return stale.count
    }
}
