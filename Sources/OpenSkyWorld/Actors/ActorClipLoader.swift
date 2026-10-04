// The shared off-main loader for actor animation clips during play: idles, gaits,
// and combat reactions. See docs/decisions/concurrency.md.

import OpenSkyFormatsAnimation
import OpenSkyGameData

/// One clip retargeted to one skeleton.
nonisolated public struct ActorClipKey: Hashable, Sendable {
    public let skeletonMeshPath: String
    public let animationPath: String

    public init(skeletonMeshPath: String, animationPath: String) {
        self.skeletonMeshPath = skeletonMeshPath
        self.animationPath = animationPath
    }
}

public typealias ActorClipLoader = AssetLoader<ActorClipKey, ActorAnimationClip>

extension AssetLoader where Key == ActorClipKey, Value == ActorAnimationClip {
    /// Reads and decodes clips from `files` on the shared play-time queue.
    public static func clips(files: any GameFileSource) -> ActorClipLoader {
        ActorClipLoader(worker: SerialAssetLoadWorker(load: load(files: files)))
    }

    /// The decode a worker runs, also for a test's immediate worker.
    nonisolated public static func load(
        files: any GameFileSource
    ) -> @Sendable (ActorClipKey) throws -> ActorAnimationClip {
        { key in
            try ActorAnimationClipLoader.clip(
                skeletonMeshPath: key.skeletonMeshPath,
                animationPath: key.animationPath,
                readHKX: { try HKXFile(data: files.contents(forPath: $0)) }
            )
        }
    }
}
