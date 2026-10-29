// Which beast form the player has taken. `Game.SetBeastForm` marks the change, and the
// race the change script sets says which form it is (UESP "Skyrim:Lycanthropy" and
// "Skyrim:Vampire Lord"). See docs/engine/beast-forms.md.

import OpenSkyWorldInterface

nonisolated public enum PlayerBeastForm: String, CaseIterable, Equatable, Sendable {
    case none
    case werewolf
    case vampireLord
    /// `SetBeastForm(true)` with a race neither vanilla change script sets, such as a mod's.
    case otherBeast

    /// The races `PlayerWerewolfChangeScript` and `DLC1PlayerVampireChangeScript` set.
    public static let werewolfRace = "WerewolfBeastRace"
    public static let vampireLordRace = "DLC1VampireBeastRace"

    /// The race decides once the script has set it; until then the flag alone marks a form.
    public static func resolve(beastFormFlag: Bool, raceEditorID: String?) -> Self {
        switch raceEditorID {
        case werewolfRace: .werewolf
        case vampireLordRace: .vampireLord
        default: beastFormFlag ? .otherBeast : .none
        }
    }

    public var isBeast: Bool {
        self != .none
    }

    /// A race without "Can Pick Up Items" takes nothing, in any form. A beast cannot start a
    /// conversation. Containers, doors, and locks stay with the Filter Activation perks
    /// the change effects add, so a corpse still offers "Feed".
    public func refusal(
        for action: InteractionAction, raceCanPickUpItems: Bool
    ) -> ActivationRefusal? {
        switch action {
        case .take where !raceCanPickUpItems: .beastForm
        case .talk where isBeast: .beastForm
        default: nil
        }
    }
}
