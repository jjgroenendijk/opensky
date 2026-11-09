// The session members its port spells in interface types.

import OpenSkyPlayer
public import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkyWorld

extension GameSession {
    public var dialogueRestorePose: FreeFlyCamera? {
        dialogueCameraState.restorePose
    }

    public func knockPlayer(_ velocity: SIMD3<Float>) {
        walkController.knock(velocity)
    }
}
