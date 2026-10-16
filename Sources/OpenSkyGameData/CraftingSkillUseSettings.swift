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

    public static let vanilla = Self()
    /// The factor of the improving formula players measured (UESP "Skyrim talk:Smithing").
    public static let temperFactor: Float = 3.8

    public init() {}

    /// Experience for making `count` items of base value `value`.
    public func constructed(value: Float, count: Int) -> Float {
        let each = constructConst + constructMult * pow(max(0, value), constructExponent)
        return each * Float(max(0, count))
    }

    /// Experience for raising an item's value by `valueGain` over `levels` quality levels.
    public func tempered(valueGain: Float, levels: Int) -> Float {
        temperMult * Self.temperFactor * sqrt(max(0, valueGain)) * sqrt(Float(max(0, levels)))
    }

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fConstructibleSkillUseConst", into: &settings, \.constructConst)
        store.read("fConstructibleSkillUseMult", into: &settings, \.constructMult)
        store.read("fConstructibleSkilluseExp", into: &settings, \.constructExponent)
        store.read("fTemperingSkillUseMult", into: &settings, \.temperMult)
        return settings
    }
}
