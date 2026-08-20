// Session wiring for character leveling (issue #499, roadmap item 20.6): builds
// the level runtime over the shared player level, hands it to skill
// advancement so a skill point banks character experience, and owns the two
// player-facing spends — the attribute pick and the perk point.
//
// AppKit stays in this controller satellite; the runtime, the curve, the tree
// index and the spend validator are engine types that build into `openskycli`
// and are testable without a window.
//
// ## Why the level runtime is wired last
//
// It writes through the actor-value runtime (the attribute pick) and reads the
// perk runtime and the AVIF index (the spend validator), so all three have to
// exist first. It is then handed *into* `SkillAdvancementRuntime`, which is a
// struct this controller owns by value — so the hand-off happens after
// `wireSkills` has stored its copy, and every later write goes through the
// controller rather than around it.
//
// Documented in docs/engine/character-leveling.md.

import AppKit

/// Character-level state the controller owns. Extensions cannot add stored
/// properties, so it lives as one value on `GameViewController`.
struct ProgressionBridgeState {
    /// Level, banked character experience, attribute picks and the perk-point
    /// pool, built by `wireProgression` when the provider can supply actor-value
    /// baselines. Nil without game data, and then nothing levels.
    var runtime: PlayerLevelRuntime?
    /// Where each perk sits in a skill's AVIF tree, which is what a spend is
    /// validated against. Empty without game data, and every spend is then
    /// refused with `.notInPerkTree` rather than accepted blind.
    var trees = PerkTreeIndex.empty
    /// The AVIF index the `World > Progression` panel browses a skill's perk
    /// tree out of (issue #500). Nil without game data, and the panel then
    /// reports itself unavailable rather than drawing an empty tree.
    var information: ActorValueInformationStore?
    /// Which skill the panel's skill controls and perk tree act on, by vanilla
    /// actor-value index. One-handed until the panel selects another.
    var skillSelection = ActorValueIdentity.firstSkillIndex
    /// Which box of that skill's tree the perk controls act on, by `INAM`.
    var nodeSelection: UInt32 = 0
    /// Human-readable result of the last level-up action.
    var lastActionText = "No leveling action yet."
}

extension GameViewController {
    /// Builds the level runtime and the perk-tree index.
    ///
    /// Wired after `wirePerks` and `wireSkills`: it hands itself to the skill
    /// runtime, and the spend validator it answers for reads the perk runtime.
    func wireProgression(provider: any CellSceneProvider) {
        guard let values = actorValues.runtime else { return }
        // The runtime publishes into the baselines it writes through, which are
        // the provider's own — so a level-up moves the player's reported level
        // and every `PC Level Mult` actor's scaling on their next read, with no
        // second reference to keep in step.
        progression.runtime = PlayerLevelRuntime(
            values: values,
            settings: (provider as? ProgressionDataProviding)?.characterLevelSettings
                ?? .documentedDefaults
        )
        if
            let perkStore = (provider as? ProgressionDataProviding)?.perkStore,
            let information = (provider as? ProgressionDataProviding)?.actorValueInformation
        {
            progression.trees = PerkTreeIndex(information: information, perks: perkStore)
            progression.information = information
            progression.nodeSelection = progressionFirstNode(
                forSkill: progression.skillSelection
            )
        }
        skills.runtime?.leveling = progression.runtime
    }

    // MARK: - Spending

    /// Spends one owed attribute pick on `kind`.
    ///
    /// - Returns: the progress afterwards, or why it was refused.
    @discardableResult
    func choosePlayerAttribute(_ kind: ActorValueKind) -> PlayerProgressResult {
        guard let runtime = progression.runtime else {
            return .failure(.noAttributePickOwed)
        }
        return runtime.chooseAttribute(kind)
    }

    /// Spends one perk point on `perk`, after the tree, the rank order and the
    /// perk's own conditions have all agreed.
    ///
    /// The point is taken *after* the grant, so a grant that somehow fails
    /// cannot leave the player a point short — and the grant goes through
    /// `addPerk`, so the abilities it brings are applied in the same call.
    ///
    /// - Returns: the progress afterwards, or why the spend was refused.
    @discardableResult
    func spendPerkPoint(on perk: ReferenceKey) -> PlayerProgressResult {
        guard let runtime = progression.runtime, let perks = perks.runtime else {
            return .failure(.noPerkPoints)
        }
        guard runtime.perkPoints > 0 else { return .failure(.noPerkPoints) }
        let validator = PerkTreeSpendValidator(runtime: perks, trees: progression.trees)
        if
            let refusal = validator.refusal(
                for: perk,
                on: runtime.holder,
                conditions: runtimeStateConditionContext()
            )
        {
            return .failure(.perkRefused(refusal))
        }
        guard addPerk(perk, to: runtime.holder) else {
            return .failure(.perkRefused(.alreadyOwned))
        }
        return runtime.spendPerkPoint()
    }

    /// Why `perk` cannot be bought right now, or nil when it can. What item
    /// 20.7 draws a tree node's availability from.
    func perkSpendRefusal(for perk: ReferenceKey) -> PerkSpendRefusal? {
        guard let perks = perks.runtime else { return .unresolvedPerk }
        let validator = PerkTreeSpendValidator(runtime: perks, trees: progression.trees)
        return validator.refusal(
            for: perk,
            on: .player,
            conditions: runtimeStateConditionContext()
        )
    }

    /// Adds or removes perk points, which is `Game.ModPerkPoints`. A zero delta
    /// is the read behind `Game.GetPerkPoints`.
    ///
    /// - Returns: the pool afterwards, or nil for a session with no leveling.
    func modifyPlayerPerkPoints(by delta: Int) -> Int? {
        guard let runtime = progression.runtime else { return nil }
        return runtime.modifyPerkPoints(by: delta).perkPoints
    }
}
