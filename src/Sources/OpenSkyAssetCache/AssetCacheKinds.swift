// The kinds of converted assets.
// See docs/engine/asset-cache.md.

import Foundation

nonisolated public enum AssetCacheKind: UInt8, CaseIterable, Sendable, CustomStringConvertible {
    case texture = 1
    case mesh = 2
    case collision = 3
    case animation = 4
    case audio = 5

    /// The folder inside the cache root that holds this kind's entries.
    public var folderName: String {
        switch self {
        case .texture: "textures"
        case .mesh: "meshes"
        case .collision: "collision"
        case .animation: "animation"
        case .audio: "audio"
        }
    }

    public var title: String {
        switch self {
        case .texture: "Textures"
        case .mesh: "Meshes"
        case .collision: "Collision"
        case .animation: "Animation"
        case .audio: "Audio"
        }
    }

    public var description: String {
        folderName
    }

    /// Kinds the cache no longer builds or reads, because they loaded no faster
    /// from it (docs/engine/asset-cache.md, "Where the cache helps").
    public static let retired: Set<Self> = [.animation, .audio]

    /// The kinds a build converts and the settings offer, in declaration order.
    public static let built = allCases.filter { !retired.contains($0) }

    public init?(folderName: String) {
        guard let kind = Self.allCases.first(where: { $0.folderName == folderName }) else {
            return nil
        }
        self = kind
    }
}
