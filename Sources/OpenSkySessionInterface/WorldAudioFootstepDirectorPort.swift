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
extension WorldAudioFootstepDirectorPort {
    public func handleActorGraphEvents(
        _ names: [String],
        gait: LocomotionGait,
        position: SIMD3<Float>,
        material: FormID?
    ) {
        handleActorGraphEvents(
            names,
            gait: gait,
            position: position,
            armatures: [],
            material: material
        )
    }

    public func handleActorGraphEvents(
        _ names: [String],
        gait: LocomotionGait,
        position: SIMD3<Float>,
        armatures: [FormID]
    ) {
        handleActorGraphEvents(
            names,
            gait: gait,
            position: position,
            armatures: armatures,
            material: nil
        )
    }

    public func handleActorGraphEvents(
        _ names: [String],
        gait: LocomotionGait,
        position: SIMD3<Float>
    ) {
        handleActorGraphEvents(names, gait: gait, position: position, armatures: [], material: nil)
    }
}
