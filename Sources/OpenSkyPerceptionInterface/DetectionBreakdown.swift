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
    /// What the target carries into the formula besides its pose: armour,
    /// light, muffle, action noise, skill, and invisibility.
    public let traits: DetectionTargetTraits
    /// The observer's Sneak skill, which UESP calls the noticer skill.
    public let noticerSkill: Float

    public var equippedWeight: Float {
        traits.equippedWeight
    }

    public init(
        distance: Float,
        hasLineOfSight: Bool = true,
        isInViewCone: Bool = true,
        isExterior: Bool = true,
        isSneaking: Bool = false,
        gait: LocomotionGait? = nil,
        traits: DetectionTargetTraits = .neutral,
        noticerSkill: Float = DetectionTargetTraits.startingSkill
    ) {
        self.distance = distance
        self.hasLineOfSight = hasLineOfSight
        self.isInViewCone = isInViewCone
        self.isExterior = isExterior
        self.isSneaking = isSneaking
        self.gait = gait
        self.traits = traits
        self.noticerSkill = noticerSkill
    }
}

/// The target-side inputs that do not come from geometry. `neutral` is a
/// target with nothing equipped, fully lit, unmuffled, silent, and at the
/// starting skill.
nonisolated public struct DetectionTargetTraits: Equatable, Sendable {
    /// 15, the vanilla starting level of every skill (UESP "Skyrim:Skills").
    public static let startingSkill: Float = 15
    public static let neutral = DetectionTargetTraits()

    /// Combined weight of the armour the target wears.
    public var equippedWeight: Float
    /// How lit the target is: 0 is dark, 1 is fully lit.
    public var lightLevel: Float
    /// The summed Muffle magnitude, the `Movement Noise Mult` actor value.
    /// 1 or more silences the armour.
    public var muffle: Float
    /// The loudness of the attack or cast the target is making now.
    public var actionSound: Float
    /// The target's Sneak skill, which UESP calls the sneaker skill.
    public var sneakSkill: Float
    /// An invisible target cannot be seen, but it can still be heard.
    public var isInvisible: Bool

    public init(
        equippedWeight: Float = 0,
        lightLevel: Float = 1,
        muffle: Float = 0,
        actionSound: Float = 0,
        sneakSkill: Float = startingSkill,
        isInvisible: Bool = false
    ) {
        self.equippedWeight = equippedWeight
        self.lightLevel = lightLevel
        self.muffle = muffle
        self.actionSound = actionSound
        self.sneakSkill = sneakSkill
        self.isInvisible = isInvisible
    }
}

/// One detection value with every term that produced it, so a readout and a
/// failing test can both say *why* a number is what it is.
nonisolated public struct DetectionBreakdown: Equatable, Sendable {
    public let soundFactor: Float
    public let visualFactor: Float
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
        value: 0
    )

    public init(
        soundFactor: Float,
        visualFactor: Float,
        value: Float
    ) {
        self.soundFactor = soundFactor
        self.visualFactor = visualFactor
        self.value = value
    }
}
