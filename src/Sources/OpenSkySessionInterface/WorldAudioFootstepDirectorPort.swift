public import OpenSkyFormatsESM
public import OpenSkyPhysics

/// What the world adapters use of `WorldAudioFootstepDirector`.
public protocol WorldAudioFootstepDirectorPort: AnyObject {
    func handleActorGraphEvents(
        _ names: [String],
        gait: LocomotionGait,
        position: SIMD3<Float>,
        armatures: [FormID],
        material: FormID?
    )
}

/// The default arguments a protocol requirement cannot carry.
extension WorldAudioFootstepDirectorPort {}
