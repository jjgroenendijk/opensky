// What the mesh library hands actor assembly: a validated skeleton, or a
// renderable model with its bounds.

import OpenSkyFormatsCore
import OpenSkyFormatsMesh

nonisolated public enum ActorAssetFailure: Error, Equatable {
    case missing
    case invalid
}

nonisolated public struct ActorSkeletonAsset: Sendable {
    public let pathKey: String
    public let skeleton: NIFSkeleton
}

nonisolated public struct ActorRenderAsset: Sendable {
    public let model: RenderModel
    public let bounds: ModelBounds?
}

/// A head part's texture set paths, relative to `Data/textures`; nil keeps the mesh's own.
nonisolated public struct HeadPartTextures: Equatable, Sendable {
    public let diffuse: String?
    public let normal: String?
    public let detail: String?

    public init(diffuse: String?, normal: String?, detail: String?) {
        self.diffuse = diffuse
        self.normal = normal
        self.detail = detail
    }
}
