import OpenSkyCombat
import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import simd

/// Witnesses that forward to the narrow parts of `MountWorldAdapter`.
extension MountWorldAdapter {
    public func lockCandidate() -> ReferenceKey? {
        dragonRiding.lockCandidate()
    }

    public func switchCandidates() -> [ReferenceKey] {
        dragonRiding.switchCandidates()
    }

    public func allowsFlyingMountLandingRequests() -> Bool {
        dragonRiding.allowsFlyingMountLandingRequests()
    }

    public func livingActorFeet(_ key: ReferenceKey) -> SIMD3<Float>? {
        dragonRiding.livingActorFeet(key)
    }
}
