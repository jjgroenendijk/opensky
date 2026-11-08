import Foundation
import OpenSkyFormatsESM
public import OpenSkyGameData
import simd

/// The game settings the world archetypes read. Defaults are the vanilla values.
nonisolated public struct MagicHoldSettings: Equatable, Sendable {
    /// `fMagicLightForwardOffset`, `fMagicLightSideOffset`, `fMagicLightHeightOffset`.
    public var lightForwardOffset: Float = 13
    public var lightSideOffset: Float = -28
    public var lightHeightOffset: Float = -60
    /// `fMagicGuideSpacing`: world units between two hazards of a Guide trail.
    public var guideSpacing: Float = 46
    /// `iMagicGuideWaypoints`: the most hazards one trail places.
    public var guideWaypoints = 44
    /// `fMagicTelekinesisBaseDistance` times `fMagicTelekinesiDistanceMult`: how far
    /// Telekinesis reaches.
    public var telekinesisBaseDistance: Float = 2100
    public var telekinesisDistanceMult: Float = 1
    /// `fMagicTelekinesisDistanceMin`: the nearest a held object comes.
    public var telekinesisDistanceMin: Float = 64
    /// `fMagicGrabActorMinDistance`: the nearest a grabbed actor is held.
    public var grabActorMinDistance: Float = 120
    /// `fMagicGrabActorThrowForce`.
    public var grabActorThrowForce: Float = 15
    /// `fMagicVACPartTargetedMult` and `fMagicVACNoPartTargetedMult`. No vanilla plugin
    /// sets them, so OpenSky uses 1.
    public var valueAndParts = MagicValueAndPartsScale()

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fMagicLightForwardOffset", into: &settings, \.lightForwardOffset)
        store.read("fMagicLightSideOffset", into: &settings, \.lightSideOffset)
        store.read("fMagicLightHeightOffset", into: &settings, \.lightHeightOffset)
        store.read("fMagicGuideSpacing", into: &settings, \.guideSpacing)
        store.read("iMagicGuideWaypoints", into: &settings, \.guideWaypoints)
        store.read("fMagicTelekinesisBaseDistance", into: &settings, \.telekinesisBaseDistance)
        store.read("fMagicTelekinesiDistanceMult", into: &settings, \.telekinesisDistanceMult)
        store.read("fMagicTelekinesisDistanceMin", into: &settings, \.telekinesisDistanceMin)
        store.read("fMagicGrabActorMinDistance", into: &settings, \.grabActorMinDistance)
        store.read("fMagicGrabActorThrowForce", into: &settings, \.grabActorThrowForce)
        store.read("fMagicVACPartTargetedMult", into: &settings, \.valueAndParts.value)
        store.read("fMagicVACNoPartTargetedMult", into: &settings, \.valueAndParts.parts)
        return settings
    }

    /// How far Telekinesis reaches, world units.
    public var telekinesisReach: Float {
        max(0, telekinesisBaseDistance * telekinesisDistanceMult)
    }
}

/// Value and Parts scales: the related actor value's, and each body-part condition's.
nonisolated public struct MagicValueAndPartsScale: Equatable, Sendable {
    public var value: Float = 1
    public var parts: Float = 1

    public init(value: Float = 1, parts: Float = 1) {
        self.value = value
        self.parts = parts
    }
}
