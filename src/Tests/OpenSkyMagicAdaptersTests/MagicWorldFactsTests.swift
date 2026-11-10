// The world facts part reads actors, items, and skills from the ports that own them.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicAdapters
import OpenSkyProgressionInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import Testing

@MainActor
struct MagicWorldFactsTests {
    private let host = MagicHost()
    private var adapter: MagicWorldAdapter {
        MagicWorldAdapter(game: host)
    }

    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let holder = ActorValueHolder(key: actor, subject: .actor(base: FormID(0x21)))

    @Test func withoutASessionNoDayHasPassed() {
        #expect(adapter.gameDaysPassed == 0)
        #expect(adapter.inventory == nil)
    }

    @Test func aSkillUseIsAdjustedForDifficultyFirst() {
        let use = SkillUseEvent(actor: .player, action: .lockpick, amount: 1)
        let harder = SkillUseEvent(actor: .player, action: .lockpick, amount: 2)
        host.fakeCombat.adjustingForDifficultyResult = harder
        host.fakeProgression.reportSkillUseResult = 4
        #expect(adapter.reportSkillUse(use) == 4)
        #expect(host.fakeProgression.reportSkillUseCalls == [harder])
    }

    @Test func actorsComeFromTheActorWorld() {
        let world = host.fakeActorWorld
        world.actorValueHolderResult = Self.holder
        world.regeneratingHoldersResult = [Self.holder]
        world.nearestActorValueHolderResult = Self.holder
        world.combatActorsResult = [CombatActorObservation(key: Self.actor, feet: .zero)]
        #expect(adapter.actorValueHolder(for: Self.actor) == Self.holder)
        #expect(adapter.regeneratingHolders() == [Self.holder])
        #expect(adapter.nearestActorValueHolder() == Self.holder)
        #expect(adapter.residentActorKeys() == [Self.actor])
        #expect(world.actorValueHolderCalls == [Self.actor])
    }

    @Test func itemsAndNoticesReachTheirPorts() {
        host.fakeInventory.nameResult = "Wheat"
        host.fakeInventory.learnEatenIngredientResult = AlchemyActionOutcome.idle
        #expect(adapter.itemName(FormID(0x40)) == "Wheat")
        adapter.playerAteIngredient(FormID(0x40))
        adapter.postNotification("Hello")
        adapter.announceSpellLearned("Flames")
        #expect(host.fakeInventory.learnEatenIngredientCalls == [FormID(0x40)])
        #expect(host.fakeMessages.postNotificationCalls == ["Hello"])
        #expect(host.fakeMessages.postWorldNoticeCalls.count == 1)
    }

    @Test func aBookRaisesOneSkillPointForEachIncrement() {
        host.fakeProgression.incrementSkillResult = true
        #expect(adapter.raiseSkillFromBook(12, points: 3) == 3)
        #expect(adapter.raiseSkillFromBook(12, points: -1) == 0)
        #expect(host.fakeProgression.incrementSkillCalls == [12, 12, 12])
    }

    @Test func perksModifyAndChooseThroughThePerkPort() {
        host.fakePerks.modifiedValueAtOnSubjectsSeamsResult = 9
        let subjects = PerkEvaluationSubjects(owner: .player)
        let value = adapter.perkModified(
            3, at: .modSpellMagnitude, on: .player, given: (subjects, ConditionContext())
        )
        #expect(value == 9)
        #expect(adapter.perkChoices(
            at: .modSpellMagnitude, on: .player, subjects: subjects, seams: ConditionContext()
        ).isEmpty)
        #expect(host.fakePerks.choicesCalls.count == 1)
    }
}
