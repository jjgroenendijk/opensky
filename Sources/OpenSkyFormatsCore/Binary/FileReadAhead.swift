// Starts reading a whole file into the page cache before a walk needs it. A walk
// over a mapped file otherwise faults its pages in one at a time, which costs
// seconds on an external disk.

import Darwin
import Foundation

nonisolated public enum FileReadAhead {
    /// Asks the kernel to read the file in the background and returns at once.
    /// A failure only loses the hint, so it is not reported.
    public static func start(_ url: URL) {
        guard LoadOptimisations.isOn(.pluginReadAhead) else { return }
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { return }
        var offset: off_t = 0
        while offset < status.st_size {
            let count = Int32(min(status.st_size - offset, off_t(Int32.max)))
            var advice = radvisory(ra_offset: offset, ra_count: count)
            guard fcntl(descriptor, F_RDADVISE, &advice) != -1 else { return }
            offset += off_t(count)
        }
    }
}
