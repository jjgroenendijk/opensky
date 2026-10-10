// What the perception pass shows a person: flat values, testable without a
// window. `summaryLine` is the per-actor line behind the `DetectionStatsLabel`
// identifier. See docs/engine/detection.md.

import Foundation
import OpenSkyFormatsESM
import simd

/// One observer's regard for one target, as a panel or a transcript shows it.
nonisolated public struct DetectionPairReadout: Equatable, Sendable {
    public let observer: ReferenceKey
    public let observerName: String
    public let target: ReferenceKey
    public let targetName: String
    public let state: DetectionState
    /// Accumulated awareness, 0 through 100.
    public let level: Float
    /// The detection value the last evaluation produced.
    public let detectionValue: Float
    public let distance: Float
    public let hasLineOfSight: Bool
    public let isInViewCone: Bool
    /// Where the target was last perceived, or nil when nothing is remembered.
    public let lastKnownPosition: SIMD3<Float>?

    /// The `DetectionStatsLabel` line: state, level, and last-seen position.
    public var summaryLine: String {
        let seen = lastKnownPosition.map {
            String(format: "last seen (%.0f, %.0f, %.0f)", $0.x, $0.y, $0.z)
        } ?? "nothing remembered"
        return String(
            format: "%@ -> %@: %@, level %.0f, value %.1f, %.0f units, %@, %@",
            observerName,
            targetName,
            state.rawValue,
            level,
            detectionValue,
            distance,
            hasLineOfSight ? (isInViewCone ? "in sight" : "out of cone") : "blocked",
            seen
        )
    }

    public init(
        observer: ReferenceKey,
        observerName: String,
        target: ReferenceKey,
        targetName: String,
        state: DetectionState,
        level: Float,
        detectionValue: Float,
        distance: Float,
        hasLineOfSight: Bool,
        isInViewCone: Bool,
        lastKnownPosition: SIMD3<Float>?
    ) {
        self.observer = observer
        self.observerName = observerName
        self.target = target
        self.targetName = targetName
        self.state = state
        self.level = level
        self.detectionValue = detectionValue
        self.distance = distance
        self.hasLineOfSight = hasLineOfSight
        self.isInViewCone = isInViewCone
        self.lastKnownPosition = lastKnownPosition
    }
}

/// The whole pass as one value: what it tracked, what it cost, and what it
/// dropped.
nonisolated public struct PerceptionReadout: Equatable, Sendable {
    public let pairs: [DetectionPairReadout]
    public let observerCount: Int
    public let targetCount: Int
    /// Pairs the cap refused to track, so a truncated list never reads as a
    /// complete one.
    public let droppedPairCount: Int
    public let lineOfSightQueryCount: Int
    public let stepCount: Int
    /// What each target brings into the formula this frame.
    public let targets: [DetectionTargetReadout]

    public static let empty = PerceptionReadout(
        pairs: [],
        observerCount: 0,
        targetCount: 0,
        droppedPairCount: 0,
        lineOfSightQueryCount: 0,
        stepCount: 0
    )

    /// Every pair involving `actor` on either side, which is what a
    /// per-selected-actor panel shows.
    public func pairs(involving actor: ReferenceKey) -> [DetectionPairReadout] {
        pairs.filter { $0.observer == actor || $0.target == actor }
    }

    public init(
        pairs: [DetectionPairReadout],
        observerCount: Int,
        targetCount: Int,
        droppedPairCount: Int,
        lineOfSightQueryCount: Int,
        stepCount: Int,
        targets: [DetectionTargetReadout] = []
    ) {
        self.pairs = pairs
        self.observerCount = observerCount
        self.targetCount = targetCount
        self.droppedPairCount = droppedPairCount
        self.lineOfSightQueryCount = lineOfSightQueryCount
        self.stepCount = stepCount
        self.targets = targets
    }
}

/// One target's non-geometric inputs, as the Detection section shows them.
nonisolated public struct DetectionTargetReadout: Equatable, Sendable {
    public let name: String
    public let traits: DetectionTargetTraits

    public init(name: String, traits: DetectionTargetTraits) {
        self.name = name
        self.traits = traits
    }

    public var summaryLine: String {
        String(
            format: "%@: light %.2f, armour weight %.1f, muffle %.2f, action %.0f, Sneak %.0f%@",
            name,
            traits.lightLevel,
            traits.equippedWeight,
            traits.muffle,
            traits.actionSound,
            traits.sneakSkill,
            traits.isInvisible ? ", invisible" : ""
        )
    }
}
