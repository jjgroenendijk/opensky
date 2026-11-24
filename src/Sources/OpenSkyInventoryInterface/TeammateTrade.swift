import OpenSkyFormatsESM
public import OpenSkyGameData

nonisolated public enum TeammateTradeText: String, GameSettingTextKey {
    /// Follows the follower's name.
    case overencumbered = "sTeammateOverencumbered"
    /// A gift the receiver cannot carry.
    case itemTooHeavy = "sItemTooHeavy"

    public var fallback: String {
        switch self {
        case .overencumbered: "can't carry any more."
        case .itemTooHeavy: "The item is too heavy to carry."
        }
    }
}
