// Drops files from the macOS page cache, so a benchmark can measure a cold read
// without `sudo purge`. `msync` with `MS_INVALIDATE` on a read-only mapping
// discards the clean pages of the file; this is how `vmtouch -e` works on macOS.

import Darwin
import Foundation

nonisolated public enum PageCacheEviction {
    /// Evicts every regular file under `folders`. Returns the bytes evicted.
    @discardableResult
    public static func evict(folders: [URL]) -> UInt64 {
        var total: UInt64 = 0
        for folder in folders {
            let files = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey]
            )
            while let url = files?.nextObject() as? URL {
                total += evict(file: url)
            }
        }
        return total
    }

    /// Evicts one file. A file that cannot be opened or mapped counts as 0 bytes.
    @discardableResult
    public static func evict(file: URL) -> UInt64 {
        let descriptor = open(file.path(percentEncoded: false), O_RDONLY)
        guard descriptor >= 0 else { return 0 }
        defer { close(descriptor) }
        var info = stat()
        guard
            fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
            info.st_size > 0
        else {
            return 0
        }
        let length = Int(info.st_size)
        let mapping = mmap(nil, length, PROT_READ, MAP_SHARED, descriptor, 0)
        guard let mapping, mapping != MAP_FAILED else { return 0 }
        defer { munmap(mapping, length) }
        return msync(mapping, length, MS_INVALIDATE) == 0 ? UInt64(length) : 0
    }
}
