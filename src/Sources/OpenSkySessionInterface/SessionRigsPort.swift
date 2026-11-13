import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyGameData
import OpenSkyPhysics
public import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// The player body, the first-person arms, and their camera states. Part of `GameSessionPort`.
public protocol SessionRigsPort: AnyObject {
    associatedtype PlayerFirstPersonRig: PlayerFirstPersonRigPort
    associatedtype PlayerBody: PlayerBodyPort
    var cinematicCameraState: RendererCinematicCameraState { get set }
    var firstPersonArmsEnabled: Bool { get set }
    var firstPersonCamera: FirstPersonCamera { get set }
    var playerBody: PlayerBody? { get }
    var playerFirstPersonRig: PlayerFirstPersonRig? { get }
}
