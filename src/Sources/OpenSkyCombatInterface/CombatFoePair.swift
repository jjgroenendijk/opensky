public import OpenSkyFormatsESM

/// Two NPCs where the observer is hostile to the target. The combat loop finds them, and
/// perception tracks each pair so the observer can detect its foe.
nonisolated public struct CombatFoePair: Hashable, Comparable, Sendable {
    public let observer: ReferenceKey
    public let target: ReferenceKey

    public init(observer: ReferenceKey, target: ReferenceKey) {
        self.observer = observer
        self.target = target
    }

    public static func < (lhs: CombatFoePair, rhs: CombatFoePair) -> Bool {
        (lhs.observer, lhs.target) < (rhs.observer, rhs.target)
    }
}
