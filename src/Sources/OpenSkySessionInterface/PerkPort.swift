public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyProgressionInterface

/// What the world adapters use of `PerkCoordinator`.
public protocol PerkPort: AnyObject {
    associatedtype PerkRuntime: PerkRuntimePort
    @discardableResult func add(_ perk: ReferenceKey, to holder: ActorValueHolder) -> Bool
    func choices(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: (ReferenceKey) -> PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> [PerkEntryPointChoice]
    func modified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder,
        lock: ReferenceKey,
        level: UInt8
    ) -> Float
    func modified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: (ReferenceKey) -> PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> Float
    func multiplier(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        target: ReferenceKey?,
        attacker: ReferenceKey?
    ) -> Float
    func ownership(of key: ReferenceKey) -> Set<ReferenceKey>?
    @discardableResult func remove(_ perk: ReferenceKey, from holder: ActorValueHolder) -> Bool
    var runtime: PerkRuntime? { get }
}

/// The default arguments a protocol requirement cannot carry.
extension PerkPort {
    @discardableResult public func multiplier(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        target: ReferenceKey?
    ) -> Float {
        multiplier(at: entryPoint, on: key, target: target, attacker: nil)
    }

    @discardableResult public func multiplier(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey
    ) -> Float {
        multiplier(at: entryPoint, on: key, target: nil, attacker: nil)
    }
}
