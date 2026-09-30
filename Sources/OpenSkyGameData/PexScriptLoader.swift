// PEX path policy and VFS loading. Canonicalization is a pure transform so
// tests and callers can use it without touching the filesystem.

import Foundation
import OpenSkyFormatsPEX

nonisolated public final class PexScriptLoader {
    public static let scriptPrefix = "scripts\\"
    public static let scriptSuffix = ".pex"

    private let fileSystem: any GameFileSource

    public init(fileSystem: any GameFileSource) {
        self.fileSystem = fileSystem
    }

    /// Every archive-provided script, path-sorted and deduplicated by the VFS.
    public func scriptPaths() -> [String] {
        fileSystem.archiveEntries()
            .map(\.path)
            .filter {
                $0.hasPrefix(Self.scriptPrefix) && $0.hasSuffix(Self.scriptSuffix)
            }
            .sorted()
    }

    public func load(_ name: String) throws -> PexFile {
        try Self.load(name) { try fileSystem.contents(forPath: $0) }
    }

    /// Loads through an injectable closure: the VFS in production, a stub in
    /// unit tests.
    public static func load(
        _ name: String,
        load: (String) throws -> Data
    ) throws -> PexFile {
        guard let path = canonicalScriptPath(name) else {
            throw VFSError.invalidPath(name)
        }
        return try PexFile(data: load(path))
    }

    /// Bare `NAME`, `scripts\NAME`, `data\scripts\NAME.pex` and
    /// separator-led forms all become `scripts\name.pex`. A colon is rejected
    /// before normalization so a Windows drive or URL cannot become a VFS key.
    public static func canonicalScriptPath(_ name: String) -> String? {
        guard !name.contains(":") else { return nil }
        guard var normalized = try? VirtualFileSystem.normalize(name) else {
            return nil
        }
        if normalized.hasPrefix("data\\") {
            normalized.removeFirst("data\\".count)
        }
        if !normalized.hasPrefix(scriptPrefix) {
            normalized = scriptPrefix + normalized
        }
        if !normalized.hasSuffix(scriptSuffix) {
            normalized += scriptSuffix
        }
        return normalized
    }
}
