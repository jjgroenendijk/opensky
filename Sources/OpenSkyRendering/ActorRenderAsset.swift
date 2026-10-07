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
