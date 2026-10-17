// What the door coordinator asks the app to do. See docs/engine/coordinators.md.

import simd

/// One change to the session outside the door motion.
nonisolated public enum SequenceDoorCommand: Equatable, Sendable {
    /// A text key the door's sequence passed, such as `Sound: DRSWoodGateHelgenOpen`.
    case textKey(String, reference: UInt32)
    /// Each leaf's model-frame move from rest, or nil when the door left.
    case setLeaves([float4x4]?, reference: UInt32)
}
