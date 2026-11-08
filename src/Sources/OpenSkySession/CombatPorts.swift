public import OpenSkyCombat
public import OpenSkySessionInterface

extension ArcheryRuntime: ArcheryRuntimePort {}
extension CombatBehaviorMachine: CombatBehaviorMachinePort {}
extension CombatCoordinator: CombatPort {}
extension CombatLoopRuntime: CombatLoopRuntimePort {}
extension ExplosionRuntime: ExplosionRuntimePort {}
extension ImpulseRuntime: ImpulseRuntimePort {}
extension KnockdownTracker: KnockdownTrackerPort {}
extension MeleeCombatRuntime: MeleeCombatRuntimePort {}
extension MeleeCombatState: MeleeCombatStatePort {}
extension MeleeImpactResolver: MeleeImpactResolverPort {}
extension PlayerDeath: PlayerDeathPort {}
extension ProjectileRuntime: ProjectileRuntimePort {}
extension RagdollCoordinator: RagdollPort {}
extension RagdollRuntime: RagdollRuntimePort {}
