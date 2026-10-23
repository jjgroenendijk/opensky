// Clearing one skill's perk tree and refunding its points, two ways: a legendary
// skill (UESP Skyrim:Skills) also drops the skill to `fLegendarySkillResetValue`, and
// the Dragonborn altar (`DLC2MiraakAltarScript`) costs a dragon soul and keeps the
// skill. See docs/engine/character-leveling.md.

import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface

/// Why a tree was not cleared. Not a bool, because the skills menu and the readout show it.
nonisolated public enum PerkTreeResetRefusal: Error, Equatable, Sendable {
    case notASkill
    /// No leveling or no perk data in this session.
    case noProgression
    /// A legendary skill needs a base of 100; carries the base it has.
    case belowLegendaryLevel(Float)
    case noDragonSoul
    /// The altar refuses a tree with nothing to refund (`DLC2AltarNoPerksInThisSkillMSG`).
    case noPerksInTree
}

nonisolated public struct PerkTreeResetReport: Equatable, Sendable {
    /// One per rank, so a perk with three ranks refunds three points.
    public let refundedPoints: Int
    public let perkPoints: Int
    public let legendaryCount: Int
}

public typealias PerkTreeResetResult = Result<PerkTreeResetReport, PerkTreeResetRefusal>

extension ProgressionCoordinator {
    /// The base level a skill must reach before it can be made legendary.
    public static let legendaryLevel = SkillAdvancement.skillCeiling

    /// Nil when `index` can be made legendary now.
    public func legendaryRefusal(forSkill index: Int32) -> PerkTreeResetRefusal? {
        guard ActorValueIdentity.isSkill(index: index) else { return .notASkill }
        guard let leveling else { return .noProgression }
        let base = leveling.values.baseValue(at: index, on: .player) ?? 0
        return base >= Self.legendaryLevel ? nil : .belowLegendaryLevel(base)
    }

    /// Drops the skill to the reset level, clears its experience, and refunds every
    /// perk of its tree. Character level and experience stay.
    @discardableResult
    public func makeSkillLegendary(_ index: Int32) -> PerkTreeResetResult {
        if let refusal = legendaryRefusal(forSkill: index) {
            return .failure(refusal)
        }
        guard let leveling else { return .failure(.noProgression) }
        let refunded = clearTree(ofSkill: index)
        let level = leveling.settings.legendaryResetLevel
        leveling.values.setBase(at: index, to: level, on: .player)
        if let slot = ActorValueIdentity.skillAdvanceIndex(forSkill: index) {
            leveling.values.setBase(at: slot, to: 0, on: .player)
        }
        leveling.noteLegendary(skill: index)
        let report = finish(index, refunded: refunded)
        record(.madeLegendary(skill: skillName(index), refunded: refunded))
        return .success(report)
    }

    /// The Dragonborn altar: one dragon soul clears one tree and refunds its points.
    @discardableResult
    public func resetPerkTree(_ index: Int32) -> PerkTreeResetResult {
        guard ActorValueIdentity.isSkill(index: index) else { return .failure(.notASkill) }
        guard let leveling, perks.runtime != nil else { return .failure(.noProgression) }
        guard !ownedTreePerks(ofSkill: index).isEmpty else { return .failure(.noPerksInTree) }
        guard
            let souls = ActorValueIdentity.index(named: "Dragon Souls"),
            (leveling.values.value(at: souls, on: .player) ?? 0) >= 1
        else { return .failure(.noDragonSoul) }
        leveling.values.addModifier(-1, to: .permanent, at: souls, on: .player)
        let refunded = clearTree(ofSkill: index)
        record(.treeReset(skill: skillName(index), refunded: refunded))
        return .success(finish(index, refunded: refunded))
    }

    /// Every owned rank of every box in the tree, rank by rank.
    public func ownedTreePerks(ofSkill index: Int32) -> [ReferenceKey] {
        guard let runtime = perks.runtime else { return [] }
        let owned = Set(runtime.state(of: .player).owned)
        return perkKeys(forSkill: index).flatMap { head -> [ReferenceKey] in
            guard let resolved = runtime.perks.perk(key: head) else { return [] }
            return runtime.perks.rankChain(from: resolved.id)
                .map { ReferenceKey(resolved: $0.id) }
                .filter(owned.contains)
        }
    }

    // MARK: - Private

    private func clearTree(ofSkill index: Int32) -> Int {
        var refunded = 0
        for perk in ownedTreePerks(ofSkill: index) where perks.remove(perk, from: .player) {
            refunded += 1
        }
        if refunded > 0 {
            _ = leveling?.modifyPerkPoints(by: refunded)
        }
        treeCounts.invalidate()
        return refunded
    }

    private func finish(_ index: Int32, refunded: Int) -> PerkTreeResetReport {
        let state = leveling?.state ?? PlayerProgressState()
        return PerkTreeResetReport(
            refundedPoints: refunded,
            perkPoints: state.perkPoints,
            legendaryCount: state.legendaryCount(ofSkill: index)
        )
    }
}
