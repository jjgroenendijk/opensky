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

    public init(facts: [ReferenceKey: ReferenceMotionFacts]?) {
        self.facts = facts
    }

    func facts(of key: ReferenceKey) -> ReferenceMotionFacts? {
        facts?[key]
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
