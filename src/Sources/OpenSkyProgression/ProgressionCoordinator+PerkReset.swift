// Clearing one skill's perk tree and refunding its points, two ways: a legendary
// skill (UESP Skyrim:Skills) also drops the skill to `fLegendarySkillResetValue`, and
// the Dragonborn altar (`DLC2MiraakAltarScript`) costs a dragon soul and keeps the
// skill. See docs/engine/character-leveling.md.

import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyProgressionInterface

nonisolated public struct PerkTreeResetReport: Equatable, Sendable {
    /// One per rank, so a perk with three ranks refunds three points.
    public let refundedPoints: Int
    let perkPoints: Int
    let legendaryCount: Int
}

public typealias PerkTreeResetResult = Result<PerkTreeResetReport, PerkTreeResetRefusal>

extension ProgressionCoordinator {
    /// Nil when `index` can be made legendary now.
    public func legendaryRefusal(forSkill index: Int32) -> PerkTreeResetRefusal? {
        perkReset.legendaryRefusal(forSkill: index)
    }

    /// Drops the skill to the reset level, clears its experience, and refunds every
    /// perk of its tree. Character level and experience stay.
    @discardableResult
    public func makeSkillLegendary(_ index: Int32) -> PerkTreeResetResult {
        let result = perkReset.makeLegendary(index)
        if case let .success(report) = result {
            record(.madeLegendary(skill: skillName(index), refunded: report.refundedPoints))
        }
        return result
    }

    /// The Dragonborn altar: one dragon soul clears one tree and refunds its points.
    @discardableResult
    func resetPerkTree(_ index: Int32) -> PerkTreeResetResult {
        let result = perkReset.resetTree(index)
        if case let .success(report) = result {
            record(.treeReset(skill: skillName(index), refunded: report.refundedPoints))
        }
        return result
    }

    var perkReset: PerkTreeReset {
        PerkTreeReset(leveling: leveling, perks: perks, reader: treeReader)
    }
}

/// Part of `ProgressionCoordinator`: clears one skill's tree and refunds its points.
@MainActor
struct PerkTreeReset {
    let leveling: PlayerLevelRuntime?
    let perks: PerkCoordinator
    let reader: ProgressionTreeReader

    /// The base level a skill must reach before it can be made legendary.
    static let legendaryLevel = SkillAdvancement.skillCeiling

    func legendaryRefusal(forSkill index: Int32) -> PerkTreeResetRefusal? {
        guard ActorValueIdentity.isSkill(index: index) else { return .notASkill }
        guard let leveling else { return .noProgression }
        let base = leveling.values.baseValue(at: index, on: .player) ?? 0
        return base >= Self.legendaryLevel ? nil : .belowLegendaryLevel(base)
    }

    func makeLegendary(_ index: Int32) -> PerkTreeResetResult {
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
        return .success(finish(index, refunded: refunded))
    }

    func resetTree(_ index: Int32) -> PerkTreeResetResult {
        guard ActorValueIdentity.isSkill(index: index) else { return .failure(.notASkill) }
        guard let leveling, perks.runtime != nil else { return .failure(.noProgression) }
        guard !reader.ownedTreePerks(ofSkill: index).isEmpty else {
            return .failure(.noPerksInTree)
        }
        guard
            let souls = ActorValueIdentity.index(named: "Dragon Souls"),
            (leveling.values.value(at: souls, on: .player) ?? 0) >= 1
        else { return .failure(.noDragonSoul) }
        leveling.values.addModifier(-1, to: .permanent, at: souls, on: .player)
        return .success(finish(index, refunded: clearTree(ofSkill: index)))
    }

    // MARK: - Private

    private func clearTree(ofSkill index: Int32) -> Int {
        var refunded = 0
        for perk in reader.ownedTreePerks(ofSkill: index) where perks.remove(perk, from: .player) {
            refunded += 1
        }
        if refunded > 0 {
            _ = leveling?.modifyPerkPoints(by: refunded)
        }
        reader.invalidateCounts()
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
