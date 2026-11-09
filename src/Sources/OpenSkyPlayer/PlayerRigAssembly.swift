// The player's rigs are assembled on the cell build queue, because the builder and
// its mesh caches live there. The main actor binds the meshes to the live pose.
// See docs/engine/player-camera.md, "The player body".

public import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyRendering
public import OpenSkyRenderResources
public import OpenSkyWorldInterface

/// The player rig the renderer draws.
public typealias PlayerRenderRig = PlayerRigAssembly<ActorRenderAsset, FaceMorphBuffer>
public typealias PlayerRenderRigResult = PlayerRigLoadResult<ActorRenderAsset, FaceMorphBuffer>

/// Where the player coordinator gets its rigs: the build queue, or a fake in tests.
public protocol PlayerRigSource: AnyObject {
    /// The mounted archives, for loading the behavior graphs and their clips.
    var playerAssetFileSystem: (any GameFileSource)? { get }
    func requestPlayerRig(_ request: PlayerRigRequest)
    /// Returns and clears every rig finished since the last drain.
    func drainPlayerRigs() -> [PlayerRenderRigResult]
}

nonisolated extension PlayerBody {
    public convenience init(
        rig: PlayerRenderRig, skeleton: HKASkeleton, pose: SkinnedPoseBuffer
    ) {
        self.init(
            assembly: rig.assembly,
            animation: SkinnedPosePlayback(
                skeleton: skeleton, pose: pose, models: rig.assembly.models.map(\.asset.model),
                sheathNodes: rig.assembly.visual.sheathNodes
            ),
            faceMorphs: rig.faceMorphs
        )
    }
}

nonisolated extension PlayerFirstPersonRig {
    public convenience init(
        rig: PlayerRenderRig, skeleton: HKASkeleton, pose: SkinnedPoseBuffer
    ) {
        self.init(
            assembly: rig.assembly,
            animation: SkinnedPosePlayback(
                skeleton: skeleton, pose: pose, models: rig.assembly.models.map(\.asset.model),
                sheathNodes: rig.assembly.visual.sheathNodes
            )
        )
    }
}
