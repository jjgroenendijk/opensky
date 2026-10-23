// What the ragdoll coordinator asks the app to do. See docs/engine/coordinators.md.

import OpenSkyFormatsESM
import simd

/// One change to the world outside the ragdoll domain.
nonisolated public enum RagdollCommand: Equatable, Sendable {
    /// An actor died this frame: crime records the murder, the kill camera may run.
    case reportMurder(ReferenceKey)
    /// The bone matrices the scene draws, by bone name, keyed by the ACHR form ID.
    case publishPoses([UInt32: [String: float4x4]])
    /// An actor at zero health kneels instead of dying: it stops fighting and scripts hear it.
    case enterBleedout(ReferenceKey)
    /// The actor stands up with at least this share of its health.
    case leaveBleedout(ReferenceKey)
}
