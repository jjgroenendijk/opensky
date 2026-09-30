// Session wiring for skill advancement: builds the runtime over the provider's
// AVIF index, answers what a hit target is wearing, and receives every skill
// use. `reportSkillUse` here satisfies `MeleeCombatWorld`, `CombatLoopWorld`,
// `ProjectileWorld` and `CasterWorld` at once, so blows, arrows and casts share
// one code path (docs/engine/skill-advancement.md).

import AppKit
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState

/// Skill-advancement state the controller owns. Extensions cannot add stored
/// properties, so it lives as one value on `GameViewController`.
struct SkillBridgeState {
    /// Use-to-experience-to-level conversion, built by `wireSkills` when the
    /// provider can supply an AVIF index. Nil without game data, and then every
    /// reported use is counted and dropped.
    var runtime: SkillAdvancementRuntime?
    /// The last advance, for the Progression readouts.
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

    /// What `key` is wearing, counted by armor type. Only equipped armor
    /// counts; clothing trains neither armor skill. Without an equipment
    /// runtime or item index the answer is "nothing worn", so no skill is
    /// guessed. The item index is the melee runtime's, to avoid a second decode.
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
    /// The read-modify-write lives here, because `SkillAdvancementRuntime` is a
    /// value this controller owns; a copy would drop the write.
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
