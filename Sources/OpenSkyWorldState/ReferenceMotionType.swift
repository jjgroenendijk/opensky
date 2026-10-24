// The Havok motion type a script set with `SetMotionType`. A cell build reads it to
// decide whether the reference's collision simulates or stays put
// (docs/engine/traps.md#motion-type).

import Foundation

nonisolated public enum ReferenceMotionType: UInt8, WorldStateComponent, Hashable, Sendable {
    /// Simulated: every body with mass falls and can be pushed.
    case dynamic = 1
    /// Held in place: moved only by a script or an animation.
    case keyframed = 4

    public static var componentKind: WorldStateComponentKind {
        .motionType
    }

    /// The Papyrus `Motion_*` value. The inertia variants simulate and fixed holds;
    /// `Motion_Character` (7) belongs to actors and is not a reference's.
    public init?(papyrusValue: Int32) {
        switch papyrusValue {
        case 1, 2, 3, 6: self = .dynamic
        case 4, 5: self = .keyframed
        default: return nil
        }
    }
}

nonisolated extension WorldStateComponentKind {
    public static let motionType = Self(rawValue: "motionType", order: 43)
}
