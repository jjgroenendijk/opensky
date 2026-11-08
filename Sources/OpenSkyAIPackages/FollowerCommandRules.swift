// Follower command mode: whether a follower agrees to use the target the player picked,
// and what it then does. See docs/engine/follower-commands.md.

import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyInventoryInterface
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

nonisolated public enum FollowerCommandRules {
    /// Morality 3, for a follower whose value cannot be read: it commits no crime.
    public static let lawfulMorality: Float = 3

    /// Morality 0 commits any crime, 1 also attacks enemies, 2 only steals, and 3 none
    /// (UESP "Skyrim:Followers", Morality).
    public static func allows(_ crime: FollowerCommandCrime?, morality: Float) -> Bool {
        switch crime {
        case nil: true
        case .property: morality <= 2
        case .violence: morality <= 0
        }
    }

    public static func decide(
        _ target: FollowerCommandTarget?, follower: ReferenceKey, morality: Float
    ) -> FollowerCommandDecision {
        guard let target else { return .refuse(.nothing) }
        guard target.key != follower else { return .refuse(.itself) }
        guard !target.noFavorAllowed else { return .refuse(.noFavorAllowed) }
        if let lock = target.lock, !lock.isPickable {
            return .refuse(.needsKey)
        }
        let task = task(for: target)
        guard allows(task.crime, morality: morality) else {
            return .moralRefusal(task.crime ?? .property)
        }
        return .agree(task)
    }

    static func task(for target: FollowerCommandTarget) -> FollowerCommandTask {
        let unlocks = target.lock != nil
        let action: FollowerCommandTask.Action = switch target.kind {
        case .item: .pickUp
        case .container, .corpse: .loot
        case .actor: .attack
        case .door, .activator, .furniture: .activate
        case .ground: .moveTo
        }
        let crime: FollowerCommandCrime? = switch action {
        case .attack: target.isHostile ? nil : .violence
        case .pickUp, .loot: target.isOwned ? .property : nil
        case .activate: unlocks && target.isOwned ? .property : nil
        case .moveTo: nil
        }
        return FollowerCommandTask(action: action, target: target, unlocks: unlocks, crime: crime)
    }
}
