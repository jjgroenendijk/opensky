import OpenSkyFormatsESM
public import OpenSkyGameData

nonisolated public enum TeammateTradeText: String, GameSettingTextKey {
    case cannotTakeOutfit = "sTeammateCantTakeOutfit"
    /// Follows the follower's name.
    case overencumbered = "sTeammateOverencumbered"
    /// A gift the receiver cannot carry.
    case itemTooHeavy = "sItemTooHeavy"

    public var fallback: String {
        switch self {
        case .cannotTakeOutfit: "You can't take your teammate's starting armor."
        case .overencumbered: "can't carry any more."
        case .itemTooHeavy: "The item is too heavy to carry."
        }
    }
}
