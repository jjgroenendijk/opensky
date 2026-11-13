// The skill experience that making and improving an item gives. UESP "Skyrim:Leveling"
// gives the making formula. See docs/engine/crafting.md.

import Foundation

nonisolated public struct CraftingSkillUseSettings: Equatable, Sendable {
    /// `fConstructibleSkillUseConst`, `...Mult`, and `fConstructibleSkilluseExp`:
    /// one made item gives `const + mult × value^exp`.
    public var constructConst: Float = 25
    public var constructMult: Float = 3
    public var constructExponent: Float = 0.65
    /// `fTemperingSkillUseMult`: scales the improving formula.
    public var temperMult: Float = 1
    /// `fTemperingSkillUseItemValConst`, `...Mult`, and `...Exp`: the item value term.
    public var temperValueConst: Float = 25
    public var temperValueMult: Float = 8
    public var temperValueExponent: Float = 0.6
    /// `fHealthDataValue1`: an item's condition at the first quality level. Each level
    /// adds the same step over the plain condition 1.
    public var firstLevelCondition: Float = 1.1

    public static let vanilla = Self()

    public init() {}

    /// Experience for making `count` items of base value `value`.
    public func constructed(value: Float, count: Int) -> Float {
        let each = constructConst + constructMult * pow(max(0, value), constructExponent)
        return each * Float(max(0, count))
    }

    /// Experience for raising an item of base value `value` by `levels` quality levels:
    /// condition gain x mult x (max(1, value)^exp x value mult + const).
    public func tempered(value: Float, levels: Int) -> Float {
        let conditionGain = Float(max(0, levels)) * (firstLevelCondition - 1)
        let valueTerm = pow(max(1, value), temperValueExponent) * temperValueMult
        return conditionGain * temperMult * (valueTerm + temperValueConst)
    }

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fConstructibleSkillUseConst", into: &settings, \.constructConst)
        store.read("fConstructibleSkillUseMult", into: &settings, \.constructMult)
        store.read("fConstructibleSkilluseExp", into: &settings, \.constructExponent)
        store.read("fTemperingSkillUseMult", into: &settings, \.temperMult)
        store.read("fTemperingSkillUseItemValConst", into: &settings, \.temperValueConst)
        store.read("fTemperingSkillUseItemValMult", into: &settings, \.temperValueMult)
        store.read("fTemperingSkillUseItemValExp", into: &settings, \.temperValueExponent)
        store.read("fHealthDataValue1", into: &settings, \.firstLevelCondition)
        return settings
    }
}
