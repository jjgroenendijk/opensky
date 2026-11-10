public import OpenSkyFormatsESM
public import OpenSkyPhysics

/// What the world adapters use of `WorldAudioFootstepDirector`.
public protocol WorldAudioFootstepDirectorPort: AnyObject {
    func handleActorGraphEvents(
        _ names: [String],
        gait: LocomotionGait,
        position: SIMD3<Float>,
        surface: (armatures: [FormID], material: FormID?)
    )
}
