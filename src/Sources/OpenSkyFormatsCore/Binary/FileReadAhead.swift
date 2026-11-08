// Starts reading a whole file, or a range of a mapped file, into the page cache
// before a read needs it. A read of a mapped file otherwise faults its pages in
// one at a time, which costs seconds on an external disk.

import Darwin
public import Foundation

nonisolated public enum FileReadAhead {
    /// Asks the kernel to read the file in the background and returns at once.
    /// A failure only loses the hint, so it is not reported.
    public static func start(_ url: URL) {
        guard LoadOptimisations.isOn(.pluginReadAhead) else { return }
        let descriptor = unsafe open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        var status = stat()
        guard unsafe fstat(descriptor, &status) == 0 else { return }
        var offset: off_t = 0
        while offset < status.st_size {
            let count = Int32(min(status.st_size - offset, off_t(Int32.max)))
            var advice = radvisory(ra_offset: offset, ra_count: count)
            guard unsafe fcntl(descriptor, F_RDADVISE, &advice) != -1 else { return }
            offset += off_t(count)
        }
    }

    /// Asks the kernel to read `range` of a mapped file in one go, so a copy out of it
    /// waits for one large read instead of faulting each page in on its own.
    public static func advise(_ data: Data, range: Range<Int>) {
        guard LoadOptimisations.isOn(.archiveReadAhead), !range.isEmpty else { return }
        unsafe data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress, range.upperBound <= buffer.count else { return }
            let page = Int(getpagesize())
            let start = unsafe UInt(bitPattern: base + range.lowerBound) & ~UInt(page - 1)
            let end = unsafe UInt(bitPattern: base + range.upperBound)
            _ = unsafe madvise(
                UnsafeMutableRawPointer(bitPattern: start),
                Int(end - start),
                MADV_WILLNEED
            )
        }
    }
}
