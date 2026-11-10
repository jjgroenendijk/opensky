public import OpenSkyCombat
public import OpenSkyFormatsESM
public import OpenSkySessionInterface

extension ArcheryRuntime: ArcheryRuntimePort {}
extension CombatBehaviorMachine: CombatBehaviorMachinePort {}
extension CombatCoordinator: CombatPort {
    @discardableResult public func applyHealthDamage(
        _ amount: Float,
        to target: ReferenceKey,
        attacker: ReferenceKey?
    ) -> Bool {
        applyHealthDamage(amount, to: target, attacker: attacker, canSever: false)
    }
}

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
