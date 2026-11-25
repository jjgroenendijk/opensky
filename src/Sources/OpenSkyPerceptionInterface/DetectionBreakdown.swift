import Foundation
public import OpenSkyPhysics
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
    /// How the observer is: searching, asleep, flying, blind, or fighting someone else.
    public var observer = DetectionObserverState()
    /// The player as target, whose sneaker skill uses the `fPlayerDetection` settings.
    public var isPlayerTarget = false

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

/// The observer-side states the CK wiki's skill and visual terms read.
nonisolated public struct DetectionObserverState: Equatable, Sendable {
    /// Searching for the target, the CK wiki's Alert state.
    public var isAlert = false
    public var isSleeping = false
    public var isFlying = false
    /// The `Blindness` actor value, 0 to 100.
    public var blindness: Float = 0
    /// In combat with an actor other than the target, the CK wiki's NotCombatTarget.
    public var isFightingAnother = false
    /// A Night Eye value above 0: the observer sees a light level 3 times higher.
    public var hasNightEye = false
    /// What the observer's Ambush package makes of the target; nil without one.
    public var ambush: DetectionAmbushRole?

    public init(
        isAlert: Bool = false, isSleeping: Bool = false, isFlying: Bool = false,
        blindness: Float = 0, isFightingAnother: Bool = false
    ) {
        self.isAlert = isAlert
        self.isSleeping = isSleeping
        self.isFlying = isFlying
        self.blindness = blindness
        self.isFightingAnother = isFightingAnother
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
    /// How lit the target is, as `GetLightLevel` over 100: 0 is dark, 1 a lit day.
    public var lightLevel: Float
    /// The summed Muffle magnitude, the `Movement Noise Mult` actor value.
    /// 1 or more silences the armour.
    public var muffle: Float
    /// The loudness of the attack or cast the target is making now.
    public var actionSound: Float
    /// The share of `actionSound` a spell cast makes. A cast also leaves a sound event.
    public var castingSound: Float = 0
    /// The target's Sneak skill, which UESP calls the sneaker skill.
    public var sneakSkill: Float
    /// An invisible target cannot be seen, but it can still be heard.
    public var isInvisible: Bool
    /// The target's Mod Detection Movement perks, a factor on the Moving term of sight.
    public var movementMultiplier: Float
    /// The Size term of sight: 0.5, 1, 1.5, or 2 by the size of the target's race.
    public var sizeFactor: Float = 1
    /// Indoors, 100 times the largest channel of the cell's ambient colour. The light
    /// offset is never larger than this.
    public var interiorLightCap: Float = .infinity
    /// The player's skill after the player rule and the sneak skill perks. Nil: the
    /// formula works it out from `sneakSkill`.
    public var effectiveSneakSkill: Float?

    /// The Size term for a race size of 0 (small) to 3 (very large).
    public static func sizeFactor(raceSize: Int) -> Float {
        0.5 * Float(min(max(raceSize, 0), 3) + 1)
    }

    public init(
        equippedWeight: Float = 0,
        lightLevel: Float = 1,
        muffle: Float = 0,
        actionSound: Float = 0,
        sneakSkill: Float = startingSkill,
        isInvisible: Bool = false,
        movementMultiplier: Float = 1
    ) {
        self.equippedWeight = equippedWeight
        self.lightLevel = lightLevel
        self.muffle = muffle
        self.actionSound = actionSound
        self.sneakSkill = sneakSkill
        self.isInvisible = isInvisible
        self.movementMultiplier = movementMultiplier
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
