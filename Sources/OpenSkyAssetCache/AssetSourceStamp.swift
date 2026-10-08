// What a cache entry was built from. The entry is current only while its source
// still has the same size, modification time, and content hash.

import Foundation

nonisolated public struct AssetSourceStamp: Hashable, Sendable {
    /// The file that provides the asset: an archive name such as
    /// `Skyrim - Textures0.bsa`, or `loose` for a file under `Data/`.
    public let origin: String
    /// The normalized VFS path (docs/formats/vfs.md).
    public let path: String
    /// Size in bytes of the asset's own bytes.
    public let size: UInt64
    /// Modification time of the providing file, in whole seconds since 1970.
    public let modified: Int64
    /// `AssetContentHash` of the source bytes, or 0 when the caller did not read them.
    public let contentHash: UInt64

    public init(
        origin: String,
        path: String,
        size: UInt64,
        modified: Int64,
        contentHash: UInt64 = 0
    ) {
        self.origin = origin
        self.path = path
        self.size = size
        self.modified = modified
        self.contentHash = contentHash
    }

    /// True when `other` names the same file in the same state. A zero hash on
    /// either side means "unknown" and does not count.
    public func matches(_ other: Self) -> Bool {
        guard
            origin == other.origin, path == other.path, size == other.size,
            modified == other.modified
        else { return false }
        return contentHash == 0 || other.contentHash == 0 || contentHash == other.contentHash
    }
}

/// 64-bit FNV-1a. Cheap and stable across runs, unlike `Hasher`.
nonisolated public enum AssetContentHash {
    private static let offsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01B3

    public static func of(_ bytes: Data) -> UInt64 {
        bytes.withUnsafeBytes { buffer in
            var hash = offsetBasis
            for byte in buffer {
                hash = (hash ^ UInt64(byte)) &* prime
            }
            return hash
        }
    }

    public static func of(_ text: String) -> UInt64 {
        of(Data(text.utf8))
    }
}
