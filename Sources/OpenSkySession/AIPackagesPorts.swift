public import OpenSkyAIPackages
public import OpenSkySessionInterface

extension ActorPackageRuntime: ActorPackageRuntimePort {}
extension FollowerCommandCoordinator: FollowerCommandPort {}
extension FurnitureCoordinator: FurniturePort {}
extension FurnitureSeatLedger: FurnitureSeatLedgerPort {}
extension NPCAnimationCoordinator: NPCAnimationPort {}
extension NPCMovementRuntime: NPCMovementRuntimePort {}
extension PackageCoordinator: PackagePort {}
extension PackageOverrideExecution: PackageOverrideExecutionPort {}
