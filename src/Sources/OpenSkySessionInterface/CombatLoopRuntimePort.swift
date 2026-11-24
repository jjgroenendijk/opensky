public import OpenSkyActorsInterface
public import OpenSkyCombatInterface
public import OpenSkyFormatsESM

/// What the world adapters use of `CombatLoopRuntime`.
public protocol CombatLoopRuntimePort: CombatControlling {
    associatedtype CombatBehaviorMachine: CombatBehaviorMachinePort
    func actionFacts(of key: ReferenceKey) -> ActorActionFacts?
    /// The aggro radius zone `key` holds the player in, or nil when it does not warn.
    func aggroZone(of key: ReferenceKey) -> AggroZone?
    /// Each actor that warns a target inside its aggro radius, with its count of warnings.
    var aggroWatches: [ReferenceKey: AggroWatch] { get }
    func activity(of key: ReferenceKey) -> ActorCombatActivity
    var behaviors: [ReferenceKey: CombatBehaviorMachine] { get }
    func combatTarget(of key: ReferenceKey) -> ReferenceKey?
    func command(_ actor: ReferenceKey, by commander: ReferenceKey)
    func dismiss(_ actor: ReferenceKey)
    /// Where an NPC's weapon is, or nil when the loop tracks no draw for `key`.
    func drawState(of key: ReferenceKey) -> WeaponDrawState?
    /// True when `key` fights with a bow or a crossbow.
    func fightsRanged(_ key: ReferenceKey) -> Bool
    /// NPC pairs whose observer attacks its target on sight.
    var foePairs: Set<CombatFoePair> { get }
    /// The NPC pairs perception tracks: the foe pairs, and each calm actor beside an
    /// ally in a fight.
    var watchedPairs: Set<CombatFoePair> { get }
    /// The actors that started the fight they are in.
    var aggressors: Set<ReferenceKey> { get }
    func hostility(of key: ReferenceKey) -> ActorHostility
    var isPlayerInCombat: Bool { get }
    func noteStagger(of key: ReferenceKey)
    func phase(of key: ReferenceKey) -> CombatBehaviorPhase?
    @discardableResult func setHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool
    var state: CombatLoopState { get }
    var targets: [ReferenceKey: ReferenceKey] { get }
}
