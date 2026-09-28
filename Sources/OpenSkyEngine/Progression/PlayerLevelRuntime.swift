// Character leveling at runtime (issue #499, roadmap item 20.6): the mutation
// layer over `PlayerProgressState` — banking character experience, crossing the
// level threshold, applying an attribute pick, and handing out and taking back
// perk points.
//
// A thin layer beside `ActorValueRuntime`, following `SkillAdvancementRuntime`
// and `PerkRuntime`. Every write goes through one of those two, so a level and
// the ten points it grants land in the journal, the dirty counts and the save
// exactly like a sword's damage does.
//
// Headless and AppKit-free: this compiles into `openskycli` and is testable
// without a window. `@MainActor` only because the runtime it writes through is.
//
// Failure model: nothing here throws. An attribute pick nobody is owed and a
// perk point nobody has are refused answers rather than errors.
//
// ## When the level actually moves
//
// The moment the experience crosses the threshold. Vanilla banks the levels and
// moves the number in the HUD only once the player opens the skills menu —
// "when you do choose to level, you will be raised to the highest level earned
// through skill progression" — and `Actor.GetLevel` follows the HUD there:
// "if you have leveled up but have yet to go into the perk menu screen, this
// will still return your level seen in the HUD"
// (<https://www.creationkit.com/index.php?title=GetLevel_-_Actor>).
//
// OpenSky raises the level, the perk point and the owed attribute pick together
// at the moment they are earned, and leaves only the *choice* pending. That is
// a stated deviation, not an oversight: the confirmation step is a menu, item
// 20.7 owns menus, and a level that is earned but invisible to `GetLevel`, to
// `PC Level Mult` scaling and to every condition until a screen exists would be
// a worse answer than one that is slightly early. The owed picks queue exactly
// as vanilla queues them, so the screen 20.7 builds still has its four prompts
// in succession to make.
//
// Documented in docs/engine/character-leveling.md.

import Foundation

/// What one award of character experience did.
nonisolated struct PlayerLevelUpReport: Equatable, Sendable {
    /// The level before and after.
    let previousLevel: Int
    let level: Int
    /// Experience left banked toward the next level.
    let carriedExperience: Float
    /// Perk points owned after the award.
    let perkPoints: Int
    /// Attribute picks owed after the award.
    let pendingAttributePicks: Int

    var levelsGained: Int {
        max(0, level - previousLevel)
    }

    var didLevel: Bool {
        level > previousLevel
    }
}

/// Why an attribute pick or a perk-point spend was refused.
///
/// Typed and exhaustive rather than a bool, because every case is something a
/// level-up screen has to say out loud: item 20.7 turns each of these into the
/// reason a button is disabled.
nonisolated enum PlayerProgressError: Error, Equatable, Sendable {
    /// No attribute pick is owed.
    case noAttributePickOwed
    /// The perk-point pool is empty.
    case noPerkPoints
    /// The perk was refused by the tree (`PerkSpendRefusal` says which rule).
    case perkRefused(PerkSpendRefusal)
}

/// What a refused or accepted progress write answers with.
typealias PlayerProgressResult = Result<PlayerProgressState, PlayerProgressError>

/// Reads and mutates the player's character-level progress.
@MainActor
struct PlayerLevelRuntime {
    /// The read and write surface for the attribute pick and the carry-weight
    /// bonus that rides with a stamina pick.
    let values: ActorValueRuntime
    /// The resolved level curve and level-up rewards.
    var settings: CharacterLevelSettings

    init(
        values: ActorValueRuntime,
        settings: CharacterLevelSettings = .documentedDefaults
    ) {
        self.values = values
        self.settings = settings
        publishLevel()
    }

    /// Where the live level is published so every derivation reading it
    /// re-derives against the new number.
    ///
    /// Taken from the baselines this runtime already writes through rather than
    /// passed in: the resolver that answers "what is the player's level?" and
    /// the one that scales a `PC Level Mult` actor against it are the same
    /// value, so there is no wiring step that can connect one and forget the
    /// other.
    var levelSource: PlayerLevelSource {
        values.baselines.playerLevel
    }

    /// The player's holder, which is the only character this runtime levels.
    var holder: ActorValueHolder {
        .player
    }

    // MARK: - Reading

    var state: PlayerProgressState {
        values.store.component(PlayerProgressState.self, for: ReferenceKey.player)
            ?? PlayerProgressState()
    }

    var level: Int {
        state.level
    }

    var perkPoints: Int {
        state.perkPoints
    }

    /// What the next level costs from where the player stands.
    var experienceForNextLevel: Float {
        CharacterLeveling.experienceForNextLevel(atLevel: level, settings: settings)
    }

    // MARK: - Writing

    /// Banks `amount` of character experience and spends it against the curve.
    ///
    /// - Returns: what happened, including the no-op shape when the award did
    ///   not reach the threshold.
    @discardableResult
    func award(characterExperience amount: Float) -> PlayerLevelUpReport {
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
    func noteSkillIncreases(_ count: Int) {
        write(state.notingSkillIncreases(count))
    }

    /// Spends one owed attribute pick on `kind`.
    ///
    /// The chosen attribute gains `iAVDhmsLevelUp` points as a *base offset*,
    /// so it rides on top of whatever the records author rather than replacing
    /// it (item 20.3). A stamina pick also adds `fLevelUpCarryWeightMod` to
    /// carry weight, which UESP states as a rule of the pick rather than of
    /// stamina: "Adding to your base stamina when you level up increases your
    /// carry weight by 5. ... Temporary changes to your stamina (such as
    /// damage, drain, or fortify) do not affect your carry weight."
    /// (<https://en.uesp.net/wiki/Skyrim:Stamina>)
    ///
    /// The three values are then filled, which is the other half of accepting a
    /// level: "When you accept the new level ... your character is fully
    /// healed, regaining any Health, Magicka, and Stamina that was depleted."
    /// (<https://en.uesp.net/wiki/Skyrim:Leveling>)
    ///
    /// - Returns: the state afterwards, or `.noAttributePickOwed` when nothing
    ///   is owed. Never traps and never hands out an unpaid-for ten points.
    @discardableResult
    func chooseAttribute(_ kind: ActorValueKind) -> PlayerProgressResult {
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
    func spendPerkPoint() -> PlayerProgressResult {
        guard let spent = state.spendingPerkPoint() else {
            return .failure(.noPerkPoints)
        }
        write(spent)
        return .success(spent)
    }

    /// Adds or removes perk points outright, which is `Game.ModPerkPoints`.
    @discardableResult
    func modifyPerkPoints(by delta: Int) -> PlayerProgressState {
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
