// Reads one entry file with a single open: one open, one fstat, and one read.
// Hundreds of lookups run per cell load, so the fixed cost per entry counts.

import Foundation

nonisolated enum AssetCacheFileRead {
    /// A use date newer than this is not written again. Removal order only needs
    /// coarse ages, and each write is a metadata update on the cache disk.
    static let touchInterval = 3600

    /// The file's bytes. `touching` refreshes an old use date on the open file.
    static func read(_ url: URL, touching: Bool) -> Result<Data, POSIXError> {
        let descriptor = open(url.path(percentEncoded: false), O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return .failure(currentError()) }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return .failure(currentError()) }
        let size = Int(info.st_size)
        var bytes = Data(count: size)
        let count = bytes.withUnsafeMutableBytes { readFully(descriptor, into: $0) }
        guard count == size else {
            return .failure(count < 0 ? currentError() : POSIXError(.EIO))
        }
        if touching, time(nil) - info.st_mtimespec.tv_sec >= touchInterval {
            _ = futimens(descriptor, nil)
        }
        return .success(bytes)
    }

    private static func readFully(
        _ descriptor: Int32, into buffer: UnsafeMutableRawBufferPointer
    ) -> Int {
        var done = 0
        while done < buffer.count {
            let result = pread(
                descriptor, buffer.baseAddress?.advanced(by: done), buffer.count - done,
                off_t(done)
            )
            if result < 0, errno == EINTR {
                continue
            }
            guard result > 0 else { return result < 0 ? -1 : done }
            done += result
        }
        return done
    }

    private static func currentError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
