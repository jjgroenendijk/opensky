// BSShaderTextureSet: the texture paths a shader property points at.
// Slot 0 = diffuse, slot 1 = normal/gloss; the rest (glow/skin, height,
// environment, env mask, subsurface, backlight) are recorded but unused for
// now (todo 2.4). Paths in vanilla files vary wildly — mixed case, `\` or
// `/`, with or without the `textures\` prefix, sometimes a leading `data\`
// — so `vfsKey(for:)` canonicalizes them for VFS lookup.
//
// Reference: NifTools nif.xml (BSShaderTextureSet, SizedString).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif.md.

import Foundation

nonisolated struct NIFShaderTextureSet {
    /// Raw path strings in slot order, exactly as stored (lossy cp1252-style
    /// decode, same rationale as header strings).
    let paths: [String]

    var diffusePath: String? {
        !paths.isEmpty ? Self.vfsKey(for: paths[0]) : nil
    }

    var normalPath: String? {
        paths.count > 1 ? Self.vfsKey(for: paths[1]) : nil
    }

    init(data: Data, header: NIFHeader) throws {
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
            paths.append(GameText.decodeLossy(bytes))
        }
        self.paths = paths
    }

    /// Normalizes a stored texture path to a VFS key: lowercase, `\` -> `/`,
    /// everything before the last `textures/` component dropped, `textures/`
    /// prefix ensured. Empty -> nil.
    ///
    /// The truncation mirrors observed engine behavior (and NifSkope's
    /// resolver): vanilla meshes ship exporter-absolute paths like
    /// `textures/skyrimhd/build/pc/data/textures/clutter/…/carrot.dds`, and
    /// the game still finds `textures/clutter/…/carrot.dds`.
    static func vfsKey(for raw: String) -> String? {
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
