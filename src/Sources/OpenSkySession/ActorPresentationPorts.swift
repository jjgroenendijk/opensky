public import OpenSkyActorPresentation
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
extension FaceMorphCoordinator: FaceMorphPort {}
extension HeadTrackingCoordinator: HeadTrackingPort {}
extension IdleCoordinator: IdlePort {}
extension PlayerAnimationPlayback: PlayerAnimationPlaybackPort {}
extension VehicleCoordinator: VehiclePort {}
extension VehicleCore: VehicleCorePort {}
extension VehicleWheelRig: VehicleWheelRigPort {}
