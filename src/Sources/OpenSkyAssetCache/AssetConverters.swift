// Converters turn one source file's bytes into one cache payload. Each is pure:
// bytes and the texture output in, bytes out, with a version. A converter returns nil for a
// source it does not store, which then always loads from the original file.

public import Foundation

nonisolated public protocol AssetConverting: Sendable {
    var kind: AssetCacheKind { get }
    var version: UInt32 { get }
    /// True for the VFS paths this converter reads, such as `.dds` files.
    func accepts(path: String) -> Bool
    func convert(path: String, bytes: Data, output: AssetTextureOutput) throws -> Data?
}

/// The shipped animation file, copied out. Builds no longer use it: a copy loads no
/// faster than the archive. `asset-optimisation measure` keeps measuring it.
nonisolated public struct LooseAnimationConverter: AssetConverting {
    public init() {}

    public var kind: AssetCacheKind {
        .animation
    }

    public var version: UInt32 {
        AssetConverterVersion.animation
    }

    public func accepts(path: String) -> Bool {
        path.hasSuffix(".hkx")
    }

    public func convert(path _: String, bytes: Data, output _: AssetTextureOutput) throws -> Data? {
        bytes
    }
}
