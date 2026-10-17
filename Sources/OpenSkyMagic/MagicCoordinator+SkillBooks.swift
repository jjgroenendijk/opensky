// Skill books: reading one for the first time raises its skill one level (UESP
// "Skyrim:Skill Books"), plus the reader's Adjust Book Skill Points perks. The read
// mark is the spellbook's, so a book counts once per save.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

extension MagicCoordinator {
    /// Reads the first skill book the player carries and has not read.
    @discardableResult
    public func readFirstUnreadSkillBook() -> CastingActionOutcome {
        guard let caster else { return .unavailable }
        let book = caster.spellbook.state(of: .player)
        let unread = carriedItems { items, item in
            items.teachesSkill(item).map { (item: item, skill: $0) }
        }.first { bookKey($0.item).map { !book.hasRead($0) } ?? false }
        guard let unread else { return recordCasting(.noUnreadSkillBook) }
        return readSkillBook(unread.item, skill: unread.skill)
    }

    /// Marks `item` read and raises `skill`. A book read before raises nothing.
    @discardableResult
    func readSkillBook(_ item: FormID, skill: Int32) -> CastingActionOutcome {
        let name = world.itemName(item)
        guard let caster, let key = bookKey(item) else {
            return recordCasting(.unresolvedBook(name))
        }
        guard !caster.spellbook.read(book: key, teaching: nil, on: .player).alreadyRead else {
            return recordCasting(.bookAlreadyRead(name))
        }
        let subject = world.inventory?.baselines.items.conditionSubject(of: item)
        let points = world.perkModified(
            1,
            at: .adjustBookSkillPoints,
            on: .player,
            subjects: PerkEvaluationSubjects(owner: .player).binding(.item, to: subject),
            seams: ConditionContext()
        )
        let raised = world.raiseSkillFromBook(
            skill, points: points.isFinite ? Int(max(0, points.rounded(.down))) : 1
        )
        return recordCasting(.readSkillBook(name, levelsRaised: raised))
    }

    private func bookKey(_ item: FormID) -> ReferenceKey? {
        caster?.spellbook.spells.resolvedID(item, fromPlugin: spellPluginName ?? pluginName)
            .map(ReferenceKey.init(resolved:))
    }
}
