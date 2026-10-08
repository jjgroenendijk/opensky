// The tempering formulas from UESP "Skyrim:Smithing": the quality a skill reaches
// and the bonus a quality gives. See docs/engine/crafting.md.

import Foundation

nonisolated public enum Tempering {
    /// UESP names for levels 1 to 6. Higher levels exist past Legendary.
    public static let names = ["Fine", "Superior", "Exquisite", "Flawless", "Epic", "Legendary"]

    /// The skill offset in the UESP effective-skill formula.
    static let skillOffset: Float = 13.29

    /// `floor((effective skill + 38) * 3 / 103)`. `perk` is 1 with the matching
    /// smithing perk, which doubles the skill above the offset.
    public static func maximumLevel(smithing: Float, perk: Float = 0) -> Int32 {
        guard smithing.isFinite, perk.isFinite else { return 0 }
        let effective = (smithing - skillOffset) * (1 + max(0, perk)) + skillOffset
        return Int32(clamping: Int(max(0, ((effective + 38) * 3 / 103).rounded(.down))))
    }

    /// `(3.6 * level - 1.6) * factor`. The factor is 1 for body armor and 0.5 for
    /// everything else, weapons included.
    public static func bonus(level: Int32, isBodyArmor: Bool) -> Float {
        guard level > 0 else { return 0 }
        // Tenths, so whole levels give exact sums: 3.6 - 1.6 in Float is 2.0000002.
        return (36 * Float(level) - 16) / 10 * (isBodyArmor ? 1 : 0.5)
    }

    /// The UESP value multiplier: Fine is 1.167, Legendary 2.0.
    public static func valueMultiplier(level: Int32) -> Float {
        1 + Float(max(0, level)) / 6
    }

    public static func name(level: Int32) -> String {
        guard level > 0 else { return "plain" }
        let index = Int(level) - 1
        return index < names.count ? names[index] : "Legendary +\(index - names.count + 1)"
    }
}
