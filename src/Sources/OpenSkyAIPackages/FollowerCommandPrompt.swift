// The crosshair's words in follower command mode, as observed in the game: a living
// actor reads Attack, an open unowned container Take All, and an empty spot the
// follower can reach Wait There. See docs/engine/follower-commands.md#crosshair.

public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyWorldInterface

nonisolated public enum FollowerCommandText: String, GameSettingTextKey {
    case attack = "sAttack"
    case takeAll = "sTakeAll"
    case waitHere = "sWaitHere"

    public var fallback: String {
        switch self {
        case .attack: "Attack"
        case .takeAll: "Take All"
        case .waitHere: "Wait There"
        }
    }
}

nonisolated public enum FollowerCommandPrompt {
    /// The verb that replaces the normal one, or nil to keep it: a locked or owned
    /// container keeps Unlock, Steal From, or Search.
    public static func verb(
        for target: FollowerCommandTarget, follower: ReferenceKey
    ) -> FollowerCommandText? {
        switch target.kind {
        case .actor: target.key == follower ? nil : .attack
        case .container: target.lock == nil && !target.isOwned ? .takeAll : nil
        case .item, .door, .activator, .furniture, .corpse, .ground: nil
        }
    }
}
