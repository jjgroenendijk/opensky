// The guard every save chunk decoder runs before it reserves storage for a count.

import Foundation

nonisolated enum SaveCountCheck {
    /// Rejects a declared element count that cannot possibly fit in the bytes
    /// left, before anything reserves storage for it. Without this a corrupt
    /// four-byte count is an out-of-memory crash rather than a thrown error.
    static func validate(
        count: UInt32,
        minimumElementSize: Int,
        remaining: Int,
        chunk: String
    ) throws {
        guard Int(count) <= remaining / minimumElementSize else {
            throw OpenSkySaveError.invalidCount(
                chunk: chunk,
                count: count,
                remaining: remaining
            )
        }
    }
}
