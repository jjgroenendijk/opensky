import Foundation
import OpenSkyBehavior
public import OpenSkyFormatsESM

/// One paired animation in progress.
nonisolated public struct PairedAnimationPlay: Equatable, Sendable {
    /// The actor that started it, such as the killer.
    public let lead: ReferenceKey
    /// The other actor, such as the victim.
    public let partner: ReferenceKey
    /// The `IDLE` that started it, by editor ID.
    public let idle: String
    /// The `IDLE`'s event, which the lead's graph got.
    public let event: String
    public let start: Float
    /// False when the partner's graph did not take the event, so only the lead plays.
    public package(set) var partnerTookEvent = true
    /// Where the partner stood when the pair started; it moves from here to the mark.
    public package(set) var partnerStart: PairedActorPose?
    /// True once the partner stands on the mark.
    public package(set) var isAtMark = false
    /// True once an update ran without the partner's graph showing a synchronized clip.
    package var waitedForMark = false

    public init(
        lead: ReferenceKey, partner: ReferenceKey, idle: String, event: String, start: Float
    ) {
        self.lead = lead
        self.partner = partner
        self.idle = idle
        self.event = event
        self.start = start
    }

    public func involves(_ actor: ReferenceKey) -> Bool {
        lead == actor || partner == actor
    }
}

/// Where one actor of a pair stands: its feet, and its heading in radians about z.
nonisolated public struct PairedActorPose: Equatable, Sendable {
    public let feet: SIMD3<Float>
    public let heading: Float

    public init(feet: SIMD3<Float>, heading: Float) {
        self.feet = feet
        self.heading = heading
    }
}
