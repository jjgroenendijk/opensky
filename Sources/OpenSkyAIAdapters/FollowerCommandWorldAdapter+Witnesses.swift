import OpenSkyActors
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyDialogue
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
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
