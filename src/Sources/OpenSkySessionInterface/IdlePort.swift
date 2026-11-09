public import OpenSkyConditions
public import OpenSkyFormatsAnimation
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyWorldInterface

/// What the world adapters use of `IdleCoordinator`.
public protocol IdlePort: AnyObject {
    @discardableResult func fireIdle(
        _ idle: ResolvedFormID,
        on actor: ReferenceKey,
        target: ReferenceKey?,
        ignoringConditions: Bool
    ) -> IdleReport?
    func actionEvent(_ action: String, for actor: ReferenceKey, target: ReferenceKey?) -> String?
    func addDependent(_ dependent: ReferenceKey, of owner: ReferenceKey)
    func allowPreviousMarker(_ actor: ReferenceKey)
    @discardableResult func enterFurniture(_ actor: ReferenceKey, use: FurnitureUse) -> IdleReport?
    var furnitureResolution: FurnitureConditionResolution { get }
    func holdsMarker(_ actor: ReferenceKey) -> Bool
    func idleBone(of actor: ReferenceKey, named bone: String) -> SIMD3<Float>?
    func idleBoneForward(of actor: ReferenceKey, named bone: String) -> SIMD3<Float>?
    func idleStart(of actor: ReferenceKey) -> Float?
    func isExitLoading(_ actor: ReferenceKey) -> Bool
    func lastReport(of actor: ReferenceKey) -> IdleReport?
    @discardableResult func leaveFurniture(_ actor: ReferenceKey, playsExit: Bool) -> IdleReport?
    func leaveMarker(_ actor: ReferenceKey)
    func ownGraphEvent(_ name: String, from actor: ReferenceKey) -> String
    func pairedAnimation(of actor: ReferenceKey) -> PairedAnimationPlay?
    var pairs: [PairedAnimationPlay] { get }
    func removeDependent(_ dependent: ReferenceKey, of owner: ReferenceKey)
    func rootMotion(of actor: ReferenceKey) -> (motion: AnimationRootMotion, elapsed: Float)?
    func startKillMove(
        _ action: String,
        attacker: ReferenceKey,
        target: ReferenceKey,
        kills: Bool
    ) -> Bool
    var store: IdleStore? { get }

    func idleSnapshot(for actor: ReferenceKey?) -> IdleControlSnapshot

    func advance()
}

/// The default arguments a protocol requirement cannot carry.
extension IdlePort {
    @discardableResult public func fireIdle(
        _ idle: ResolvedFormID,
        on actor: ReferenceKey,
        ignoringConditions: Bool
    ) -> IdleReport? {
        fireIdle(idle, on: actor, target: nil, ignoringConditions: ignoringConditions)
    }

    @discardableResult public func leaveFurniture(_ actor: ReferenceKey) -> IdleReport? {
        leaveFurniture(actor, playsExit: true)
    }
}
