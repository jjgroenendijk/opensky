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
    /// leading `data/` stripped, `textures/` prefix ensured. Empty -> nil.
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
        guard !path.isEmpty else { return nil }
        if !path.hasPrefix("textures/") {
            path = "textures/" + path
        }
        return path
    }
}
