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
    public func readFirstUnreadSkillBook() -> String {
        guard let caster else { return MagicCore.castingUnavailableText }
        let book = caster.spellbook.state(of: .player)
        let unread = carriedItems { items, item in
            items.teachesSkill(item).map { (item: item, skill: $0) }
        }.first { bookKey($0.item).map { !book.hasRead($0) } ?? false }
        guard let unread else {
            castingActionText = "The player carries no unread skill book."
            return castingActionText
        }
        return readSkillBook(unread.item, skill: unread.skill)
    }

    /// Marks `item` read and raises `skill`. A book read before raises nothing.
    @discardableResult
    func readSkillBook(_ item: FormID, skill: Int32) -> String {
        let name = world?.itemName(item) ?? item.description
        guard let caster, let key = bookKey(item) else {
            castingActionText = "Could not resolve \(name)."
            return castingActionText
        }
        guard !caster.spellbook.read(book: key, teaching: nil, on: .player).alreadyRead else {
            castingActionText = "\(name) was already read."
            return castingActionText
        }
        let subject = world?.inventory?.baselines.items.conditionSubject(of: item)
        let points = world?.perkModified(
            1,
            at: .adjustBookSkillPoints,
            on: .player,
            subjects: PerkEvaluationSubjects(owner: .player).binding(.item, to: subject),
            seams: ConditionContext()
        ) ?? 1
        let raised = world?.raiseSkillFromBook(
            skill, points: points.isFinite ? Int(max(0, points.rounded(.down))) : 1
        ) ?? 0
        castingActionText = "Read \(name): the skill rose \(raised) level(s)."
        return castingActionText
    }

    private func bookKey(_ item: FormID) -> ReferenceKey? {
        caster?.spellbook.spells.resolvedID(item, fromPlugin: spellPluginName ?? pluginName)
            .map(ReferenceKey.init(resolved:))
    }
}
