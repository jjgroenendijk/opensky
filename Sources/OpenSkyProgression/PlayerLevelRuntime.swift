// Character leveling: banking experience, crossing the threshold, attribute picks
// and perk points, all written through `ActorValueRuntime` and `PerkRuntime`.
// Nothing throws; an unowed pick is a refused answer. Deviation: the level moves as
// soon as it is earned, not when the skills menu opens (vanilla, per
// <https://www.creationkit.com/index.php?title=GetLevel_-_Actor>); only the choice
// waits. See docs/engine/character-leveling.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface
import OpenSkyWorldState

/// What one award of character experience did.
nonisolated public struct PlayerLevelUpReport: Equatable, Sendable {
    /// The level before and after.
    public let previousLevel: Int
    public let level: Int
    /// Experience left banked toward the next level.
    public let carriedExperience: Float
    /// Perk points owned after the award.
    public let perkPoints: Int
    /// Attribute picks owed after the award.
    public let pendingAttributePicks: Int

    public var levelsGained: Int {
        max(0, level - previousLevel)
    }

    public var didLevel: Bool {
        level > previousLevel
    }
}

/// Why an attribute pick or perk-point spend was refused. Not a bool, because the level-up
/// screen shows each case as the reason a button is disabled.
nonisolated public enum PlayerProgressError: Error, Equatable, Sendable {
    /// No attribute pick is owed.
    case noAttributePickOwed
    /// The perk-point pool is empty.
    case noPerkPoints
    /// The perk was refused by the tree (`PerkSpendRefusal` says which rule).
    case perkRefused(PerkSpendRefusal)
}

/// What a refused or accepted progress write answers with.
public typealias PlayerProgressResult = Result<PlayerProgressState, PlayerProgressError>

/// Reads and mutates the player's character-level progress.
@MainActor
public struct PlayerLevelRuntime {
    /// The read and write surface for the attribute pick and the carry-weight
    /// bonus that rides with a stamina pick.
    public let values: any ActorValueAccess
    /// The resolved level curve and level-up rewards.
    public var settings: CharacterLevelSettings

    public init(
        values: any ActorValueAccess,
        settings: CharacterLevelSettings = .documentedDefaults
    ) {
        self.values = values
        self.settings = settings
        publishLevel()
    }

    /// Where the live level is published, taken from the baselines this runtime
    /// writes through, so no wiring step can connect one reader and forget another.
    public var levelSource: PlayerLevelSource {
        values.baselines.playerLevel
    }

    /// The player's holder, which is the only character this runtime levels.
    public var holder: ActorValueHolder {
        .player
    }

    // MARK: - Reading

    public var state: PlayerProgressState {
        values.store.component(PlayerProgressState.self, for: ReferenceKey.player)
            ?? PlayerProgressState()
    }

    public var level: Int {
        state.level
    }

    public var perkPoints: Int {
        state.perkPoints
    }

    /// What the next level costs from where the player stands.
    public var experienceForNextLevel: Float {
        CharacterLeveling.experienceForNextLevel(atLevel: level, settings: settings)
    }

    // MARK: - Writing

    /// Banks `amount` of character experience and spends it against the curve.
    ///
    /// - Returns: what happened, including the no-op shape when the award did
    ///   not reach the threshold.
    @discardableResult
    public func award(characterExperience amount: Float) -> PlayerLevelUpReport {
        let banked = state.banking(experience: amount)
        let outcome = CharacterLeveling.advance(
            experience: banked.experience,
            from: banked.level,
            settings: settings
        )
        return write(banked.leveled(outcome), from: banked.level)
    }

    /// Notes `count` skill points gained, which the level-up screen counts
    /// separately from the experience they banked.
    public func noteSkillIncreases(_ count: Int) {
        write(state.notingSkillIncreases(count))
    }

    /// Spends one owed attribute pick on `kind`: `iAVDhmsLevelUp` as a base offset,
    /// plus `fLevelUpCarryWeightMod` carry weight for stamina (UESP Skyrim:Stamina).
    /// The three values are then refilled (UESP Skyrim:Leveling). Returns
    /// `.noAttributePickOwed` when nothing is owed.
    @discardableResult
    public func chooseAttribute(_ kind: ActorValueKind) -> PlayerProgressResult {
        guard let chosen = state.choosing(kind) else {
            return .failure(.noAttributePickOwed)
        }
        values.incrementBase(
            at: ActorValueIdentity.index(of: kind),
            by: settings.attributeIncrement,
            on: holder
        )
        if kind == .stamina {
            values.incrementBase(
                at: ActorValueIdentity.carryWeightIndex,
                by: settings.carryWeightPerStaminaPick,
                on: holder
            )
        }
        write(chosen)
        values.restoreAll(on: holder)
        return .success(chosen)
    }

    /// Takes one perk point out of the pool.
    ///
    /// - Returns: the state afterwards, or `.noPerkPoints`.
    @discardableResult
    public func spendPerkPoint() -> PlayerProgressResult {
        guard let spent = state.spendingPerkPoint() else {
            return .failure(.noPerkPoints)
        }
        write(spent)
        return .success(spent)
    }

    /// Adds or removes perk points outright, which is `Game.ModPerkPoints`.
    @discardableResult
    public func modifyPerkPoints(by delta: Int) -> PlayerProgressState {
        let modified = state.modifyingPerkPoints(by: delta)
        write(modified)
        return modified
    }

    // MARK: - Private

    /// Stores `state`, dropping the slot once it says nothing, and republishes
    /// the level so every `PC Level Mult` derivation re-derives against it.
    @discardableResult
    private func write(
        _ state: PlayerProgressState,
        from previousLevel: Int? = nil
    ) -> PlayerLevelUpReport {
        let current = self.state
        if state != current {
            if state.isEmpty {
                values.store.reset(.playerProgress, for: ReferenceKey.player)
            } else {
                values.store.set(state, for: ReferenceKey.player, in: nil)
            }
        }
        publishLevel(state.level)
        return PlayerLevelUpReport(
            previousLevel: previousLevel ?? state.level,
            level: state.level,
            carriedExperience: state.experience,
            perkPoints: state.perkPoints,
            pendingAttributePicks: state.pendingAttributePicks
        )
    }

    private func publishLevel(_ level: Int? = nil) {
        levelSource.set(level ?? state.level)
    }
}
