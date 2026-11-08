// The session members its port spells in interface types.

import OpenSkyPlayer
public import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkySessionInterface
public import OpenSkyWorld

extension GameSession {
    public var dialogueRestorePose: FreeFlyCamera? {
        dialogueCameraState.restorePose
    }

    /// The session draws only the body type it builds; any other clears the body.
    public func setPlayerBody(_ body: (any PlayerBodyPort)?) throws {
        try setPlayerBody(body as? PlayerBody)
    }

    public func setPlayerFirstPersonRig(_ rig: (any PlayerFirstPersonRigPort)?) throws {
        try setPlayerFirstPersonRig(rig as? PlayerFirstPersonRig)
    }

    public func knockPlayer(_ velocity: SIMD3<Float>) {
        walkController.knock(velocity)
    }
}
