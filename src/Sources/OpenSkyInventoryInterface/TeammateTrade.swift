import OpenSkyFormatsESM
public import OpenSkyGameData

nonisolated public enum TeammateTradeText: String, GameSettingTextKey {
    case cannotTakeOutfit = "sTeammateCantTakeOutfit"
    /// Follows the follower's name.
    case overencumbered = "sTeammateOverencumbered"

    public var fallback: String {
        switch self {
        case .cannotTakeOutfit: "You can't take your teammate's starting armor."
        case .overencumbered: "can't carry any more."
        }
    }
}
