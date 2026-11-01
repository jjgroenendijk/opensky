// Follower command mode: whether a follower agrees to use the target the player picked,
// and what it then does. See docs/engine/follower-commands.md.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import simd

/// What the player pointed at, as the rules see it.
nonisolated public struct FollowerCommandTarget: Equatable, Sendable {
    nonisolated public enum Kind: String, Equatable, Sendable {
        case item, door, container, activator, furniture, actor, corpse
        /// A spot with nothing to use on it.
        case ground
    }

    /// Nil for a spot on the ground.
    public let key: ReferenceKey?
    public let kind: Kind
    public let position: SIMD3<Float>
    /// Nil for a target with no lock or an open one.
    public var lock: LockDifficulty?
    /// Taking it, or picking its lock, is theft from its owner.
    public var isOwned = false
    /// A living actor that is already the player's enemy.
    public var isHostile = false
    /// `ObjectReference.SetNoFavorAllowed`.
    public var noFavorAllowed = false

    public init(key: ReferenceKey?, kind: Kind, position: SIMD3<Float>) {
        self.key = key
        self.kind = kind
        self.position = position
    }
}

/// The crime a command asks for, which the follower's morality must allow.
nonisolated public enum FollowerCommandCrime: String, Equatable, Sendable {
    case property, violence
}

/// One accepted command.
nonisolated public struct FollowerCommandTask: Equatable, Sendable {
    nonisolated public enum Action: String, Equatable, Sendable {
        /// Use a door, lever, chair, or other activator.
        case activate
        /// Go to a spot and wait there.
        case moveTo
        case pickUp
        /// Take every item from a container or a body.
        case loot
        case attack
    }

    public let action: Action
    public let target: FollowerCommandTarget
    /// The follower opens the lock first. It needs no lockpicks.
    public let unlocks: Bool
    public let crime: FollowerCommandCrime?

    /// An attack starts combat from where the follower stands.
    public var walks: Bool {
        action != .attack
    }
}

/// Why the follower says its Refuse line.
nonisolated public enum FollowerCommandRefusal: String, Equatable, Sendable {
    case noFavorAllowed, needsKey, itself, nothing
}

nonisolated public enum FollowerCommandDecision: Equatable, Sendable {
    case agree(FollowerCommandTask)
    case refuse(FollowerCommandRefusal)
    /// The crime is past the follower's morality.
    case moralRefusal(FollowerCommandCrime)

    /// The Favors tab topic subtype the follower says (<https://ck.uesp.net/wiki/Favors_Tab>).
    public var line: FourCC {
        switch self {
        case .agree: "AGRE"
        case .refuse: "REFU"
        case .moralRefusal: "MREF"
        }
    }
}

nonisolated public enum FollowerCommandRules {
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
