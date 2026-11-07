// What the ragdoll coordinator asks the app to do. See docs/engine/coordinators.md.

public import OpenSkyFormatsESM
public import simd

/// One change to the world outside the ragdoll domain.
nonisolated public enum RagdollCommand: Equatable, Sendable {
    /// An actor died this frame: crime records the murder, the kill camera may run.
    case reportMurder(ReferenceKey)
    /// The bone matrices the scene draws, by bone name, keyed by the ACHR form ID.
    case publishPoses([UInt32: [String: float4x4]])
    /// The player body's simulated bones by name; empty returns the body to its graph.
    case publishPlayerRagdoll([String: float4x4])
    /// The bone matrices of each cut head, keyed by the ACHR form ID it came from.
    case publishSeveredHeads([UInt32: [String: float4x4]])
    /// An actor at zero health kneels instead of dying: it stops fighting and scripts hear it.
    case enterBleedout(ReferenceKey)
    /// The actor stands up with at least this share of its health.
    case leaveBleedout(ReferenceKey)
    /// A living actor fell as a ragdoll: it stops moving and fighting until it is up.
    case enterKnockdown(ReferenceKey)
    /// The actor starts its get-up clip, standing at `feet` and facing `yaw`, or as it
    /// faced when no neck bone shows the way.
    case getUp(ReferenceKey, feet: SIMD3<Float>, yaw: Float?)
    /// The knockdown is over: the actor stood up, died, or left the loaded cells.
    case endKnockdown(ReferenceKey)
}
