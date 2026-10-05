// The whole install's size per asset kind and texture role, in the units the
// processing time scales with: texels for textures, stored bytes otherwise
// (docs/tools/asset-format-comparison.md).

import Foundation
import OpenSkyFormatsMesh
import OpenSkyGameData

nonisolated public struct AssetCensusBucket: Codable, Equatable, Sendable {
    public let kind: AssetKind
    public let role: TextureRole?
    public var fileCount = 0
    public var workUnits = 0
    public var storedBytes = 0
    /// Files that could not be read or parsed; they add no work units.
    public var unreadableCount = 0

    public init(kind: AssetKind, role: TextureRole?) {
        self.kind = kind
        self.role = role
    }
}

nonisolated public struct AssetCensus: Codable, Equatable, Sendable {
    public let buckets: [AssetCensusBucket]

    public init(buckets: [AssetCensusBucket]) {
        self.buckets = buckets
    }

    /// Walks every archive entry of `kinds`. Textures are read for their texel
    /// count; the other kinds only need the stored size.
    public static func count(
        files: any GameFileSource,
        storedSize: (String) -> Int?,
        kinds: Set<AssetKind>
    ) -> Self {
        var buckets: [String: AssetCensusBucket] = [:]
        for entry in files.archiveEntries() {
            for (kind, role) in classify(entry.path) where kinds.contains(kind) {
                let key = "\(kind.rawValue)/\(role?.rawValue ?? "")"
                var bucket = buckets[key] ?? AssetCensusBucket(kind: kind, role: role)
                let stored = storedSize(entry.path) ?? 0
                bucket.fileCount += 1
                bucket.storedBytes += stored
                if kind == .texture {
                    if let texels = texelCount(files, entry.path) {
                        bucket.workUnits += texels
                    } else {
                        bucket.unreadableCount += 1
                    }
                } else {
                    bucket.workUnits += stored
                }
                buckets[key] = bucket
            }
        }
        return Self(buckets: buckets.keys.sorted().compactMap { buckets[$0] })
    }

    /// The kinds a path counts as. A NIF is both a mesh and a collision source.
    static func classify(_ path: String) -> [(AssetKind, TextureRole?)] {
        let lower = path.lowercased()
        let name = (lower.split(separator: "\\").last).map(String.init) ?? lower
        switch (name as NSString).pathExtension {
        case "dds" where lower.hasPrefix("textures\\"):
            return [(.texture, textureRole(name))]
        case "nif" where lower.hasPrefix("meshes\\"):
            return [(.mesh, nil), (.collision, nil)]
        case "hkx" where lower.contains("\\animations\\"):
            return [(.animation, nil)]
        case "wav", "xwm", "fuz":
            return [(.audio, nil)]
        default:
            return []
        }
    }

    /// The role a texture's name suffix gives it, as the game's naming convention uses.
    static func textureRole(_ name: String) -> TextureRole {
        let stem = (name as NSString).deletingPathExtension
        guard let suffix = stem.split(separator: "_").last.map({ "_" + $0 }) else {
            return .color
        }
        if ["_n", "_msn"].contains(suffix) {
            return .normal
        }
        return dataSuffixes.contains(suffix) ? .data : .color
    }

    private static let dataSuffixes: Set = [
        "_s", "_sk", "_em", "_e", "_g", "_m", "_p", "_b", "_h"
    ]

    private static func texelCount(_ files: any GameFileSource, _ path: String) -> Int? {
        guard let dds = try? DDSFile(data: files.contents(forPath: path)) else { return nil }
        return (0 ..< dds.mipCount).map { dds.width(level: $0) * dds.height(level: $0) }
            .reduce(0, +)
    }
}
