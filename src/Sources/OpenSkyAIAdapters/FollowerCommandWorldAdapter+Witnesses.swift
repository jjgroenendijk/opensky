import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Witnesses that forward to the narrow parts of `FollowerCommandWorldAdapter`.
extension FollowerCommandWorldAdapter {
    public func commandTarget(_ key: ReferenceKey) -> FollowerCommandTarget? {
        tasks.commandTarget(key)
    }

    public func performFollowerTask(_ task: FollowerCommandTask, follower: ReferenceKey) -> Bool {
        tasks.performFollowerTask(task, follower: follower)
    }
}
