// The use-key presses refused with a notice: actor state, used furniture, parent
// activation, combat, and a child player.

import OpenSkyGameData
@testable import OpenSkyInventory
import OpenSkyWorldInterface
import Testing

struct ActivationRefusalRuleTests {
    private let texts = GameSettingTexts<ActivationRefusalText>.vanilla

    private func talk(_ edit: (inout ActorActivationState) -> Void) -> ActivationFacts {
        var facts = ActivationFacts(action: .talk)
        var actor = ActorActivationState(name: "Lydia")
        edit(&actor)
        facts.actor = actor
        return facts
    }

    @Test func anActorThatCannotTalkNamesItself() {
        #expect(ActivationRefusalRule.refusal(talk { $0.isFleeing = true }, texts: texts)
            == "Lydia is fleeing for their life.")
        #expect(ActivationRefusalRule.refusal(talk { $0.isUnconscious = true }, texts: texts)
            == "Lydia is unconscious.")
        #expect(ActivationRefusalRule.refusal(talk { $0.isCalmed = true }, texts: texts)
            == "Lydia is calmed and cannot respond.")
        #expect(ActivationRefusalRule.refusal(talk { $0.isInScene = true }, texts: texts)
            == "This person is busy.")
        #expect(ActivationRefusalRule.refusal(talk { _ in }, texts: texts) == nil)
    }

    @Test func aCalmedCreatureUsesTheCreatureText() {
        let facts = talk {
            $0.isCalmed = true
            $0.isCreature = true
        }
        #expect(ActivationRefusalRule.refusal(facts, texts: texts)
            == ActivationRefusalText.creatureCalmed.fallback)
    }

    @Test func furnitureAndParentActivationRefuse() {
        var facts = ActivationFacts(action: .activate)
        facts.isFurniture = true
        facts.furnitureOccupied = true
        #expect(ActivationRefusalRule.refusal(facts, texts: texts) == texts[.objectInUse])
        facts.furnitureOccupied = false
        facts.furnitureReserved = true
        #expect(ActivationRefusalRule.refusal(facts, texts: texts) == texts[.usedBySomeoneElse])
        facts.parentActivateOnly = true
        #expect(ActivationRefusalRule.refusal(facts, texts: texts) == texts[.remoteActivation])
    }

    @Test func combatAndAChildPlayerRefuse() {
        var facts = ActivationFacts(action: .activate)
        facts.blocksInCombat = true
        #expect(ActivationRefusalRule.refusal(facts, texts: texts) == nil)
        facts.playerInCombat = true
        #expect(ActivationRefusalRule.refusal(facts, texts: texts) == texts[.combat])
        var chair = ActivationFacts(action: .activate)
        chair.isFurniture = true
        chair.playerIsChild = true
        #expect(ActivationRefusalRule.refusal(chair, texts: texts) == texts[.child])
    }
}
