// What the player's behavior graph asks of the ragdolls this frame, read off the
// ragdoll modifiers it evaluated. See docs/engine/ragdoll.md.

import OpenSkyFormatsAnimation

/// The ragdoll modifier output of one graph update. Nil fields mean no such
/// modifier ran, and the runtime uses its default.
nonisolated public struct RagdollGraphControls: Equatable, Sendable {
    /// `m_durationToBlend` of `hkbRigidBodyRagdollControlsModifier`.
    public var blendDuration: Float?
    public var powered: HKBPoweredRagdollControlsModifier?
    /// The event name of an active `BSRagdollContactListenerModifier`.
    public var contactEvent: String?

    public init(
        blendDuration: Float? = nil,
        powered: HKBPoweredRagdollControlsModifier? = nil,
        contactEvent: String? = nil
    ) {
        self.blendDuration = blendDuration
        self.powered = powered
        self.contactEvent = contactEvent
    }
}
