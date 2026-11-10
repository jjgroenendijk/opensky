public import OpenSkyActorPresentation
public import OpenSkyFormatsESM
import OpenSkyPlayer
public import OpenSkySessionInterface
import OpenSkyWorldInterface

extension ActorAnimationPlayback: ActorAnimationPlaybackPort {}
extension ActorGraphCoordinator: ActorGraphPort {}
extension ActorGraphLoan: ActorGraphLoanPort {}
extension AnimationEventCoordinator: AnimationEventPort {}
extension CellAnimatedVehicle: CellAnimatedVehiclePort {}
extension DragonFlightCoordinator: DragonFlightPort {}
extension DragonFlightState: DragonFlightStatePort {}
extension FaceMorphCoordinator: FaceMorphPort {
    public func showEmotion(
        _ emotion: TopicInfo.ResponseEmotion,
        value: UInt32,
        on actor: FormID,
        time: (now: Float, seconds: Float?)
    ) {
        showEmotion(emotion, value: value, on: actor, now: time.now, seconds: time.seconds)
    }
}

extension HeadTrackingCoordinator: HeadTrackingPort {}
extension IdleCoordinator: IdlePort {}
extension NPCAnimationCoordinator: NPCAnimationPort {}
extension SkinnedPosePlayback: SkinnedPosePlaybackPort {}
extension VehicleCoordinator: VehiclePort {}
extension VehicleCore: VehicleCorePort {}
extension VehicleWheelRig: VehicleWheelRigPort {}
