// The player's rigs are assembled on the cell build queue, because the builder and
// its mesh caches live there. The main actor binds the meshes to the live pose.
// See docs/engine/player-camera.md, "The player body".

import OpenSkyActorPresentation
public import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyRendering
import OpenSkyRenderResources
public import OpenSkyWorldInterface

/// Where the player coordinator gets its rigs: the build queue, or a fake in tests.
public protocol PlayerRigSource: AnyObject {
    /// The mounted archives, for loading the behavior graphs and their clips.
    var playerAssetFileSystem: (any GameFileSource)? { get }
    func requestPlayerRig(_ request: PlayerRigRequest)
    /// Returns and clears every rig finished since the last drain.
    func drainPlayerRigs() -> [PlayerRigLoadResult]
}

nonisolated extension PlayerBody {
    public convenience init(
        rig: PlayerRigAssembly, skeleton: HKASkeleton, pose: PlayerPoseBuffer
    ) {
        self.init(
            assembly: rig.assembly,
            animation: PlayerAnimationPlayback(
                skeleton: skeleton, pose: pose, models: rig.assembly.models.map(\.asset.model),
                sheathNodes: rig.assembly.visual.sheathNodes
            ),
            faceMorphs: rig.faceMorphs
        )
    }
}

nonisolated extension PlayerFirstPersonRig {
    public convenience init(
        rig: PlayerRigAssembly, skeleton: HKASkeleton, pose: PlayerPoseBuffer
    ) {
        self.init(
            assembly: rig.assembly,
            animation: PlayerAnimationPlayback(
                skeleton: skeleton, pose: pose, models: rig.assembly.models.map(\.asset.model),
                sheathNodes: rig.assembly.visual.sheathNodes
            )
        )
    }
}
