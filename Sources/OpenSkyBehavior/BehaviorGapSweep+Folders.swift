// Which behavior files share a skeleton. An actor folder holds `behaviors...` and
// `character assets...` folders side by side, matched by their suffix:
// `canine\behaviors wolf` uses `canine\character assets wolf\skeleton.hkx`.

import Foundation

/// The behavior files of one actor folder variant, with the skeleton and clips they use.
nonisolated public struct BehaviorFileSet: Equatable, Sendable {
    /// The actor folder plus the `behaviors` folder suffix, such as `meshes\actors\canine wolf`.
    public let name: String
    public let behaviors: [String]
    public let skeleton: String?
    public let animations: [String]
    /// The `characters...` file whose properties the graphs' bindings read.
    public var character: String?
}

nonisolated extension BehaviorGapSweep {
    /// Groups `paths` (lowercased archive paths) into one set per `behaviors` folder.
    public static func fileSets(in paths: [String]) -> [BehaviorFileSet] {
        var behaviorsByKey: [String: [String]] = [:]
        for path in paths where path.hasSuffix(".hkx") {
            let parts = path.split(separator: "\\", omittingEmptySubsequences: false)
            guard
                let index = parts.indices.dropLast().first(where: {
                    $0 >= 2 && parts[$0].hasPrefix("behaviors")
                }) else { continue }
            let folder = parts[..<index].joined(separator: "\\")
            let variant = parts[index].dropFirst("behaviors".count)
            behaviorsByKey["\(folder)|\(variant)", default: []].append(path)
        }
        return behaviorsByKey.keys.sorted().map { key in
            let pieces = key.split(separator: "|", omittingEmptySubsequences: false)
            let folder = String(pieces[0])
            let variant = String(pieces[1])
            let inside = paths.filter { $0.hasPrefix(folder + "\\") }
            return BehaviorFileSet(
                name: folder + variant,
                behaviors: behaviorsByKey[key]?.sorted() ?? [],
                skeleton: asset(among: inside, folder: folder, variant: variant, kind: .skeleton),
                animations: inside.filter { $0.contains("\\animations\\") },
                character: asset(among: inside, folder: folder, variant: variant, kind: .character)
            )
        }
    }

    enum AssetKind {
        case skeleton, character

        var folder: String {
            self == .skeleton ? "characterassets" : "characters"
        }
    }

    /// A `skeleton*.hkx` in a `character assets...` folder, or a character file in a
    /// `characters...` folder, directly under `folder`. The folder with the same suffix
    /// wins, then a folder with none, then the first.
    private static func asset(
        among paths: [String],
        folder: String,
        variant: String,
        kind: AssetKind
    ) -> String? {
        let depth = folder.split(separator: "\\").count
        let candidates = paths.filter { path in
            let parts = path.split(separator: "\\")
            guard parts.count == depth + 2, let file = parts.last else { return false }
            let assets = parts[depth].replacingOccurrences(of: " ", with: "")
            let named = kind == .character || file.hasPrefix("skeleton")
            return assets.hasPrefix(kind.folder) && named
                && !file.contains("female") && file.hasSuffix(".hkx")
        }.sorted()
        func assetSuffix(_ path: String) -> String {
            let assets = path.split(separator: "\\")[depth]
            return assets.replacingOccurrences(of: " ", with: "")
                .dropFirst(kind.folder.count).description
        }
        let wanted = variant.replacingOccurrences(of: " ", with: "")
        return candidates.first { assetSuffix($0) == wanted }
            ?? candidates.first { assetSuffix($0).isEmpty }
            ?? candidates.first
    }
}
