// Skill books: reading one for the first time raises its skill one level (UESP
// "Skyrim:Skill Books"), plus the reader's Adjust Book Skill Points perks. The read
// mark is the spellbook's, so a book counts once per save.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

extension MagicCoordinator.SpellTomes {
    /// What reading `item` does: a skill book raises its skill, a spell tome teaches its
    /// spell. Nil for a book that teaches nothing.
    @discardableResult
    func readBook(_ item: FormID) -> CastingActionOutcome? {
        guard let items = coordinator.world.inventory?.baselines.items else { return nil }
        if let skill = items.teachesSkill(item) {
            return readSkillBook(item, skill: skill)
        }
        if let spell = items.teachesSpell(item) {
            return coordinator.controlPanels.readSpellTome(item, spell: spell)
        }
        return nil
    }

    /// Marks `item` read and raises `skill`. A book read before raises nothing.
    @discardableResult
    func readSkillBook(_ item: FormID, skill: Int32) -> CastingActionOutcome {
        let name = coordinator.world.itemName(item)
        guard let caster = coordinator.caster, let key = bookKey(item) else {
            return coordinator.recordCasting(.unresolvedBook(name))
        }
        guard !caster.spellbook.read(book: key, teaching: nil, on: .player).alreadyRead else {
            return coordinator.recordCasting(.bookAlreadyRead(name))
        }
        let subject = coordinator.world.inventory?.baselines.items.conditionSubject(of: item)
        let points = coordinator.world.perkModified(
            1,
            at: .adjustBookSkillPoints,
            on: .player,
            subjects: PerkEvaluationSubjects(owner: .player).binding(.item, to: subject),
            seams: ConditionContext()
        )
        let raised = coordinator.world.raiseSkillFromBook(
            skill, points: points.isFinite ? Int(max(0, points.rounded(.down))) : 1
        )
        return coordinator.recordCasting(.readSkillBook(name, levelsRaised: raised))
    }

    private func bookKey(_ item: FormID) -> ReferenceKey? {
        coordinator.caster?.spellbook.spells.resolvedID(
            item,
            fromPlugin: coordinator.spellPluginName ?? coordinator.pluginName
        )
        .map(ReferenceKey.init(resolved:))
    }
}
