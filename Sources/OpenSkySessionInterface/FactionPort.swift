public import OpenSkyActorsInterface
public import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData

/// What the world adapters use of `FactionCoordinator`.
public protocol FactionPort: AnyObject {
    associatedtype FactionRuntime: FactionRuntimePort
    associatedtype RelationshipRuntime: RelationshipRuntimePort
    func conditionResolution() -> FactionConditionResolution
    func hostility(of key: ReferenceKey) -> ActorHostility
    @discardableResult func join(
        _ faction: ReferenceKey,
        actor key: ReferenceKey,
        rank: Int8
    ) -> Bool
    @discardableResult func leave(_ faction: ReferenceKey, actor key: ReferenceKey) -> Bool
    func memberships(of key: ReferenceKey) -> ActorFactionState?
    func profile(of key: ReferenceKey) -> ActorSocialProfile?
    func reaction(of observer: ReferenceKey, toward target: ReferenceKey) -> ActorReaction?
    var relationships: RelationshipRuntime? { get }
    var runtime: FactionRuntime? { get }
    func setCrimeHostility(_ source: any CrimeHostilitySource)
    @discardableResult func setHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool
}

/// The default arguments a protocol requirement cannot carry.
extension FactionPort {
    @discardableResult public func join(_ faction: ReferenceKey, actor key: ReferenceKey) -> Bool {
        join(faction, actor: key, rank: 0)
    }
}
