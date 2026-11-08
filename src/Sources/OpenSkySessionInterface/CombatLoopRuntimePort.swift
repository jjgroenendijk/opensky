public import OpenSkyActorsInterface
public import OpenSkyCombatInterface
public import OpenSkyFormatsESM

/// What the world adapters use of `CombatLoopRuntime`.
public protocol CombatLoopRuntimePort: CombatControlling {
    associatedtype CombatBehaviorMachine: CombatBehaviorMachinePort
    func actionFacts(of key: ReferenceKey) -> ActorActionFacts?
    func activity(of key: ReferenceKey) -> ActorCombatActivity
    var behaviors: [ReferenceKey: CombatBehaviorMachine] { get }
    func combatTarget(of key: ReferenceKey) -> ReferenceKey?
    func command(_ actor: ReferenceKey, by commander: ReferenceKey)
    func dismiss(_ actor: ReferenceKey)
    func hostility(of key: ReferenceKey) -> ActorHostility
    var isPlayerInCombat: Bool { get }
    func noteStagger(of key: ReferenceKey)
    func phase(of key: ReferenceKey) -> CombatBehaviorPhase?
    @discardableResult func setHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool
    var state: CombatLoopState { get }
    var targets: [ReferenceKey: ReferenceKey] { get }
}
