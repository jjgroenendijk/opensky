import Foundation
import OpenSkyPhysics
import simd

/// Everything the detection value is computed from, for one observer and one
/// target at one instant.
///
/// A flat value rather than the two actors plus the geometry, because the
/// formula genuinely takes only these numbers, and a test that has to build a
/// world to check an exponent is a test of the wrong thing.
nonisolated public struct DetectionInputs: Equatable, Sendable {
    /// Straight-line distance between the pair, world units.
    public let distance: Float
    /// Whether static collision leaves the sight line clear. Gates the visual
    /// term outright and attenuates the sound term.
    public let hasLineOfSight: Bool
    /// Whether the target lies inside the observer's view cone. Gates the
    /// visual term and nothing else — you can hear what is behind you.
    public let isInViewCone: Bool
    /// Whether the observer stands outdoors, which extends the range both
    /// senses attenuate over.
    public let isExterior: Bool
    /// Whether the target is crouched.
    public let isSneaking: Bool
    /// How the target is moving, or nil when it is standing still.
    public let gait: LocomotionGait?
    /// Combined weight of everything the target has equipped.
    public let equippedWeight: Float

    public init(
        distance: Float,
        hasLineOfSight: Bool = true,
        isInViewCone: Bool = true,
        isExterior: Bool = true,
        isSneaking: Bool = false,
        gait: LocomotionGait? = nil,
        equippedWeight: Float = 0
    ) {
        self.distance = distance
        self.hasLineOfSight = hasLineOfSight
        self.isInViewCone = isInViewCone
        self.isExterior = isExterior
        self.isSneaking = isSneaking
        self.gait = gait
        self.equippedWeight = equippedWeight
    }
}

/// One detection value with every term that produced it, so a readout and a
/// failing test can both say *why* a number is what it is.
nonisolated public struct DetectionBreakdown: Equatable, Sendable {
    public let soundFactor: Float
    public let visualFactor: Float
    public let skillFactor: Float
    public let distanceAttenuation: Float
    /// The detection value itself. Positive means the observer is picking the
    /// target up right now; zero or negative means it is not.
    public let value: Float

    /// Whether anything is being perceived at all this instant.
    public var isPerceiving: Bool {
        value > 0
    }

    public static let none = DetectionBreakdown(
        soundFactor: 0,
        visualFactor: 0,
        skillFactor: 0,
        distanceAttenuation: 0,
        value: 0
    )

    public init(
        soundFactor: Float,
        visualFactor: Float,
        skillFactor: Float,
        distanceAttenuation: Float,
        value: Float
    ) {
        self.soundFactor = soundFactor
        self.visualFactor = visualFactor
        self.skillFactor = skillFactor
        self.distanceAttenuation = distanceAttenuation
        self.value = value
    }
}
