// Session wiring for skill advancement (issue #498, roadmap item 20.5): builds
// the advancement runtime over the provider's AVIF index, answers the one
// question a hit cannot answer about itself — what the target is wearing — and
// is the single place every simulated system's skill use lands.
//
// AppKit stays in this controller satellite; the runtime, the formulas and the
// event are engine types that build into `openskycli` and are testable without
// a window.
//
// ## One implementation for four seams
//
// `reportSkillUse` is written once here and satisfies `MeleeCombatWorld`,
// `CombatLoopWorld`, `ProjectileWorld` and `CasterWorld` at the same time,
// exactly as `reportScriptHit` does for the first three: all four refine
// `SkillUseReporting`, and this controller is the conformance for all of them.
// A blow, an arrow and a cast therefore reach the same thresholds through the
// same code, which is what stops the three from drifting apart.
//
// Documented in docs/engine/skill-advancement.md.

import AppKit

/// Skill-advancement state the controller owns. Extensions cannot add stored
/// properties, so it lives as one value on `GameViewController`.
struct SkillBridgeState {
    /// Use-to-experience-to-level conversion, built by `wireSkills` when the
    /// provider can supply an AVIF index. Nil without game data, and then every
    /// reported use is counted and dropped.
    var runtime: SkillAdvancementRuntime?
    /// The last advance, for the readouts item 20.7 builds on.
    var lastAdvance: SkillAdvanceReport?
}

extension GameViewController {
    /// Builds the advancement runtime over the provider's AVIF index.
    ///
    /// Wired after `wireActorValues`, because every read and write it makes goes
    /// through that runtime, and after `wireWorldItems`, because the worn-armour
    /// question it answers reads the equipment runtime.
    func wireSkills(provider: any CellSceneProvider) {
        guard
            let values = actorValues.runtime,
            let information = (provider as? ProgressionDataProviding)?.actorValueInformation
        else { return }
        var runtime = SkillAdvancementRuntime(
            values: values,
            parameters: SkillUseParameterSource(store: information),
            settings: (provider as? ProgressionDataProviding)?.skillAdvancementSettings
                ?? .documentedDefaults
        )
        runtime.wornArmor = { [weak self] key in
            self?.wornArmor(of: key) ?? .none
        }
        skills.runtime = runtime
    }

    /// Converts one reported use, from whichever system simulated it.
    ///
    /// - Returns: the skill experience awarded, which is zero for an NPC, for an
    ///   action no skill claims and for a session with no progression data.
    @discardableResult
    func reportSkillUse(_ use: SkillUseEvent) -> Float {
        guard var runtime = skills.runtime else { return 0 }
        let report = runtime.record(use)
        skills.runtime = runtime
        if let report {
            skills.lastAdvance = report
        }
        return report?.experience ?? 0
    }

    /// What `key` is wearing, counted by armour type.
    ///
    /// Equipped armour only: a piece in the pack teaches nothing, and clothing
    /// belongs to neither armour skill. A session with no equipment runtime or
    /// no item index answers "nothing worn", and an armoured hit then credits no
    /// skill rather than a guessed one.
    ///
    /// The item index is the melee runtime's, which is the provider's own
    /// `inventoryBaselines.items` — one store rather than a second decode of the
    /// same ARMO records.
    func wornArmor(of key: ReferenceKey) -> WornArmorProfile {
        guard
            let equipment = worldItems.equipment,
            let items = melee.weapons,
            let holder = inventoryHolder(of: key)
        else { return .none }
        var heavy = 0
        var light = 0
        for item in equipment.equipped(on: holder) {
            switch items.armorType(item) {
            case .heavy: heavy += 1
            case .light: light += 1
            case .clothing, nil: continue
            }
        }
        return WornArmorProfile(heavyPieces: heavy, lightPieces: light)
    }

    /// The inventory holder behind a reference key, which is the player's own
    /// holder for the player and an actor's for anything resident.
    private func inventoryHolder(of key: ReferenceKey) -> InventoryHolder? {
        if key == .player {
            return .player
        }
        guard
            let streamer,
            let entry = streamer.referenceEntry(key: key),
            let actor = entry.placedActor
        else { return nil }
        return InventoryHolder(
            key: key,
            owner: .actor(base: actor.base),
            cell: streamer.cellLocation(of: key)
        )
    }

    /// One scripted advance, for `Game.AdvanceSkill` and `Game.IncrementSkill`.
    ///
    /// The whole read-modify-write lives here because `SkillAdvancementRuntime`
    /// is a struct this controller owns by value — handing the bridge a copy
    /// would drop the write.
    ///
    /// - Returns: whether the skill took it.
    func advancePlayerSkill(
        _ advance: PapyrusSkillAdvance,
        at index: Int32,
        by magnitude: Float
    ) -> Bool {
        guard var runtime = skills.runtime else { return false }
        let report = switch advance {
        case .advance: runtime.advance(skill: index, byUse: magnitude, on: runtime.player)
        case .increment: runtime.increment(skill: index, on: runtime.player)
        }
        skills.runtime = runtime
        if let report {
            skills.lastAdvance = report
        }
        return report != nil
    }
}
