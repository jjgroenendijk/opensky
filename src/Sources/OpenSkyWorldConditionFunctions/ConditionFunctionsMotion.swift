// Position and movement condition functions, indices from xEdit wbDefinitionsTES5.pas:
// 6 GetPos, 25 IsMoving, 99 GetHeadingAngle, 446 GetVelocity, 584 GetRelativeAngle, 589
// GetMovementDirection, 620-623 and 683-684 the pathing reads, 639 GetWithinDistance,
// 680 GetActivatorHeight, 704 IsPathing, 720 GetTargetHeight.
// See docs/engine/condition-functions-world.md#motion.

import Foundation
public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyWorldInterface
import simd

nonisolated public struct MotionConditionResolution: ConditionResolution, Sendable {
    public static let empty = MotionConditionResolution(facts: nil)

    private let facts: [ReferenceKey: ReferenceMotionFacts]?
    private let lookup: (@MainActor @Sendable (ReferenceKey) -> ReferenceMotionFacts?)?

    public init(facts: [ReferenceKey: ReferenceMotionFacts]?) {
        self.facts = facts
        lookup = nil
    }

    /// `facts` first, then `lookup` for any other reference, read when a condition asks.
    /// Conditions run on the main actor, as the whole simulation does.
    public init(
        facts: [ReferenceKey: ReferenceMotionFacts],
        lookup: @escaping @MainActor @Sendable (ReferenceKey) -> ReferenceMotionFacts?
    ) {
        self.facts = facts
        self.lookup = lookup
    }

    func facts(of key: ReferenceKey) -> ReferenceMotionFacts? {
        if let known = facts?[key] {
            return known
        }
        guard let lookup else { return nil }
        return MainActor.assumeIsolated { lookup(key) }
    }
}

nonisolated extension ConditionContext {
    public var motion: MotionConditionResolution {
        get { self[resolution: MotionConditionResolution.self] }
        set { self[resolution: MotionConditionResolution.self] = newValue }
    }
}

nonisolated extension ReferenceMotionFacts {
    /// `ptAxis` stores the letter: 88 X, 89 Y, 90 Z.
    package static func axisIndex(_ parameter: Condition.Parameter?) -> Int? {
        switch parameter?.asInt32 {
        case 88: 0
        case 89: 1
        case 90: 2
        default: nil
        }
    }
}
