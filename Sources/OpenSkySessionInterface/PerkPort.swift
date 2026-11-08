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
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> Float
    func modified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder,
        target: ReferenceKey?,
        attacker: ReferenceKey?
    ) -> Float
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
    @discardableResult public func modified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder,
        subjects: PerkEvaluationSubjects
    ) -> Float {
        modified(value, at: entryPoint, on: holder, subjects: subjects, seams: ConditionContext())
    }

    @discardableResult public func modified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder,
        attacker: ReferenceKey?
    ) -> Float {
        modified(value, at: entryPoint, on: holder, target: nil, attacker: attacker)
    }

    @discardableResult public func modified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder,
        target: ReferenceKey?
    ) -> Float {
        modified(value, at: entryPoint, on: holder, target: target, attacker: nil)
    }

    @discardableResult public func modified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder
    ) -> Float {
        modified(value, at: entryPoint, on: holder, target: nil, attacker: nil)
    }

    @discardableResult public func multiplier(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        attacker: ReferenceKey?
    ) -> Float {
        multiplier(at: entryPoint, on: key, target: nil, attacker: attacker)
    }

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

    @discardableResult public func modified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: (ReferenceKey) -> PerkEvaluationSubjects
    ) -> Float {
        modified(value, at: entryPoint, on: key, subjects: subjects, seams: ConditionContext())
    }

    @discardableResult public func choices(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: (ReferenceKey) -> PerkEvaluationSubjects
    ) -> [PerkEntryPointChoice] {
        choices(at: entryPoint, on: key, subjects: subjects, seams: ConditionContext())
    }
}
