// The Werewolf and Vampire Lord perk trees Dawnguard adds. The trees sit on two AVIF
// records Skyrim.esm leaves without one, and the change scripts keep their points in
// globals. Observed in Dawnguard.esm; see docs/engine/beast-forms.md.

import Foundation
import OpenSkyFormatsESM

nonisolated public enum BeastPerkTree: String, CaseIterable, Sendable {
    case werewolf
    case vampireLord

    /// The tree a skills menu shows for `index`, or nil for any other actor value.
    public init?(actorValueIndex index: Int32) {
        guard let tree = Self.allCases.first(where: { $0.actorValueIndex == index }) else {
            return nil
        }
        self = tree
    }

    /// The `Werewolf Perks` or `Vampire Perks` actor value the menu names the tree by.
    public var actorValueIndex: Int32 {
        ActorValueIdentity.index(named: self == .werewolf ? "Werewolf Perks" : "Vampire Perks")
            ?? ActorValueIdentity.noneIndex
    }

    /// The AVIF whose perk tree Dawnguard fills.
    public var informationEditorID: String {
        self == .werewolf ? "AVHealRatePowerMod" : "AVMagickaRateMod"
    }

    /// The points left to spend in this tree.
    public var perkPointsGlobal: String {
        self == .werewolf ? "DLC1WerewolfPerkPoints" : "DLC1VampirePerkPoints"
    }

    /// Feeding or blood progress, and the amount the next point needs.
    public var progressGlobal: String {
        self == .werewolf ? "DLC1WerewolfFeedPoints" : "DLC1VampireBloodPoints"
    }

    public var nextPerkGlobal: String {
        self == .werewolf ? "DLC1WerewolfNextPerk" : "DLC1VampireNextPerk"
    }
}
