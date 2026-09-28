import OpenSkyFormatsESM

/// One observer-target pair's identity.
nonisolated public struct DetectionPairKey: Hashable, Comparable, Sendable {
    public let observer: ReferenceKey
    public let target: ReferenceKey

    public init(observer: ReferenceKey, target: ReferenceKey) {
        self.observer = observer
        self.target = target
    }

    public static func < (lhs: DetectionPairKey, rhs: DetectionPairKey) -> Bool {
        (lhs.observer, lhs.target) < (rhs.observer, rhs.target)
    }
}
