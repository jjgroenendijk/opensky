// A fixed `ActorValueAccess` for suites that read actor values but must not
// depend on the rules that change them.

import OpenSkyActorsInterface
import OpenSkyGameData
import OpenSkyWorldState

/// Every actor has `values`, every indexed read answers `indexedValue`, and no
/// write changes anything.
@MainActor
public struct FixedActorValues: ActorValueAccess {
    public let store: WorldStateStore
    public let baselines = ActorValueBaselineFixture.flat()
    public var values: ActorValues
    public var indexedValue: Float?

    public init(
        store: WorldStateStore = WorldStateStore(),
        values: ActorValues = ActorValues(repeating: 100),
        indexedValue: Float? = nil
    ) {
        self.store = store
        self.values = values
        self.indexedValue = indexedValue
    }

    public func baseline(of _: ActorValueHolder) -> ActorValueBaseline {
        baselines.fallback
    }

    public func maximums(of _: ActorValueHolder) -> ActorValues {
        values
    }

    public func current(of _: ActorValueHolder) -> ActorValues {
        values
    }

    public func fractions(of _: ActorValueHolder) -> ActorValues {
        ActorValues(repeating: 1)
    }

    public func hasZeroHealth(_: ActorValueHolder) -> Bool {
        false
    }

    public func damage(
        _: ActorValueKind,
        by _: Float,
        on _: ActorValueHolder
    ) -> ActorValueState {
        ActorValueState(current: values)
    }

    public func set(_: ActorValueKind, to _: Float, on _: ActorValueHolder) -> ActorValueState {
        ActorValueState(current: values)
    }

    public func restoreAll(on _: ActorValueHolder) -> ActorValueState {
        ActorValueState(current: values)
    }

    public func value(at _: Int32, on _: ActorValueHolder) -> Float? {
        indexedValue
    }

    public func baseValue(at _: Int32, on _: ActorValueHolder) -> Float? {
        indexedValue
    }

    public func entry(at _: Int32, on _: ActorValueHolder) -> ActorValueEntry? {
        nil
    }

    public func resolvedEntries(of _: ActorValueHolder) -> [Int32: ActorValueEntry] {
        [:]
    }

    public func damage(at _: Int32, by _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    public func restore(at _: Int32, by _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    public func setValue(at _: Int32, to _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    public func setBase(at _: Int32, to _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    public func incrementBase(at _: Int32, by _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    public func advanceSkill(at _: Int32, by _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    public func addModifier(
        _: Float,
        to _: ActorValueModifier,
        at _: Int32,
        on _: ActorValueHolder
    ) -> Bool {
        false
    }

    public func setModifier(
        _: Float,
        for _: ActorValueModifier,
        at _: Int32,
        on _: ActorValueHolder
    ) -> Bool {
        false
    }

    public func forceValue(at _: Int32, to _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    public func magicDamageMultiplier(
        element _: Int32?,
        on _: ActorValueHolder,
        settings _: ActorResistanceSettings
    ) -> Float {
        1
    }
}
