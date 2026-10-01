// BSShaderTextureSet: texture paths. Slot 0 is diffuse, slot 1 normal/gloss.
// Vanilla paths vary in case, slashes, and prefixes, so `vfsKey(for:)`
// normalizes them. Layout: docs/formats/nif-materials.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct NIFShaderTextureSet: Sendable {
    /// Raw path strings in slot order, exactly as stored (lossy cp1252-style
    /// decode, same rationale as header strings).
    public let paths: [String]

    public var diffusePath: String? {
        !paths.isEmpty ? Self.vfsKey(for: paths[0]) : nil
    }

    public var normalPath: String? {
        paths.count > 1 ? Self.vfsKey(for: paths[1]) : nil
    }

    public init(data: Data, header: NIFHeader) throws {
        _ = header // layout is stream-independent at 20.2.0.7
        var reader = BinaryReader(data)
        let count = try Int(reader.readUInt32())
        // Each SizedString costs at least its 4-byte length prefix.
        guard count * 4 <= reader.bytesRemaining else {
            throw NIFError.malformed("texture count \(count) exceeds block size")
        }
        var paths: [String] = []
        paths.reserveCapacity(count)
        for _ in 0 ..< count {
            let length = try Int(reader.readUInt32())
            let bytes = try reader.read(count: length)
            paths.append(GameText.decode(bytes))
        }
        self.paths = paths
    }

    /// A stored texture path as a VFS key: lowercase, `/` separators, cut to
    /// the last `textures/`. Empty gives nil. The cut matches the game, which
    /// finds exporter-absolute paths (docs/formats/nif-materials.md).
    public static func vfsKey(for raw: String) -> String? {
        var path = raw.lowercased()
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespaces)
        while path.hasPrefix("/") {
            path.removeFirst()
        }
        if path.hasPrefix("data/") {
            path.removeFirst("data/".count)
        }
        if let start = lastTexturesComponent(in: path) {
            path.removeSubrange(path.startIndex ..< start)
        }
        guard !path.isEmpty else { return nil }
        if !path.hasPrefix("textures/") {
            path = "textures/" + path
        }
        return path
    }

    /// Start of the last `textures/` path component, if any — component
    /// boundary required so `mytextures/foo.dds` is not truncated mid-word.
    private static func lastTexturesComponent(in path: String) -> String.Index? {
        var searchRange = path.startIndex ..< path.endIndex
        var found: String.Index?
        while let range = path.range(of: "textures/", range: searchRange) {
            let atStart = range.lowerBound == path.startIndex
            if atStart || path[path.index(before: range.lowerBound)] == "/" {
                found = range.lowerBound
            }
            searchRange = range.upperBound ..< path.endIndex
        }
        return found
    }
}
