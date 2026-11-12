// The Inventory world adapter answers the coordinators from the session ports.

import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyInventoryAdapters
import OpenSkyInventoryInterface
import OpenSkyMenusInterface
import OpenSkyProgressionInterface
import OpenSkyScriptingInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct InventoryWorldAdapterTests {
    private let host = InventoryHost()
    private var adapter: InventoryWorldAdapter {
        InventoryWorldAdapter(game: host, stage: nil)
    }

    private static let item = FormID(0x30)
    private static let key = InventoryAdapterFixture.key

    @Test func withoutRuntimesTheReadoutsAnswerNothing() {
        #expect(adapter.questItemBases().isEmpty)
        #expect(adapter.dropPlacement() == nil)
        #expect(adapter.nearestActorEntry() == nil)
        #expect(adapter.gameDaysPassed == nil)
        #expect(adapter.gameMonth == nil)
        #expect(adapter.playerSpeechSkill() == nil)
        #expect(adapter.pickpocketSkill(of: Self.key) == nil)
        #expect(adapter.carryWeight(of: .player) == nil)
        #expect(adapter.skillLevel(at: 0) == nil)
        #expect(adapter.itemKeywords(of: Self.item) == nil)
        #expect(adapter.hourOfDay == nil)
        #expect(adapter.totalGameHours == nil)
        #expect(!adapter.detectsPlayer(Self.key))
        #expect(adapter.pickpocketCaughtDay(of: Self.key) == nil)
    }

    @Test func readoutsForwardToTheirPorts() {
        host.fakePlayer.isSneaking = true
        host.fakeStreamer.appearanceSkipReasonsResult = ["no skeleton"]
        host.fakeCrime.theftBountyResult = 40
        host.fakeMagic.enchantmentLineResult = "Fire Damage"
        #expect(adapter.isPlayerSneaking)
        #expect(adapter.appearanceSkipReasons(forActor: Self.item) == ["no skeleton"])
        #expect(adapter.theftBounty(of: Self.item, from: Self.key) == 40)
        #expect(adapter.enchantmentLine(of: Self.item, on: Self.key) == "Fire Damage")
        #expect(host.fakeActorWorld.actorValueHolderCalls == [Self.key])
        #expect(host.fakeMagic.enchantmentLineCalls.map(\.item) == [Self.item])
    }

    @Test func theCrosshairAndBooksComeFromTheHUDAndTheBookMenu() throws {
        let book = try #require(host.fakeMenuScreens.book as? FakeBookMenuPort)
        let target = InventoryAdapterFixture.target(InventoryAdapterFixture.interaction(.take))
        host.fakeHUD.interactionTarget = target
        book.isBookResult = true
        #expect(adapter.crosshairInteraction == target.interaction)
        #expect(adapter.isBook(Self.item))
        #expect(!adapter.interactions.openBook(target.interaction))
        book.isBookResult = false
        #expect(!adapter.interactions.openBook(target.interaction))
        #expect(book.openCalls.isEmpty)
    }

    @Test func onlyAFreeChairSeatsThePlayer() throws {
        let chair = InventoryAdapterFixture.interaction(
            .activate, seats: [InventoryAdapterFixture.seat()]
        )
        #expect(!adapter.interactions.useFurniture(InventoryAdapterFixture.interaction(.activate)))
        #expect(!adapter.interactions.useFurniture(chair))
        host.fakeStreamer.referenceEntryFormIDResult = try InventoryAdapterFixture.referenceEntry()
        host.fakeFurniture.useResult = .failure(.disabled)
        #expect(!adapter.interactions.useFurniture(chair))
        host.fakeFurniture.useResult = .failure(.noFreeSeat)
        #expect(adapter.interactions.useFurniture(chair))
        #expect(host.fakeFurniture.useCalls.map(\.actor) == [.player, .player])
    }

    @Test func theSessionBuilderReadsTheSameHost() {
        #expect(adapter.sessions.game === host)
    }

    @Test func anInmateIsAskedToServeTheSentence() {
        host.fakeMapWorld.settingTextsResult = GameSettingTexts<MessageBoxText>()
        host.fakeCrime.crimeTextsValue = CrimeTexts()
        adapter.interactions.askToServeSentence()
        let call = host.fakeMessages.presentChoicesCalls.first
        #expect(call?.text == CrimeTexts().serveSentenceQuestion)
        #expect(call?.buttons.count == 2)
    }

    @Test func aCatchIsKeptInTheScriptedState() {
        let bridge = FakePapyrusWorldStateBridgePort()
        host.fakeScripts.bridge = bridge
        bridge.scriptedStateResult = ScriptedReferenceState(
            values: [ScriptedStateName.pickpocketCaughtDay: 3]
        )
        #expect(adapter.pickpocketCaughtDay(of: Self.key) == 3)
        adapter.notePickpocketCatch(on: 4, chargedTo: .player, by: Self.key)
        adapter.forgetPickpocketCatch(of: Self.key)
        #expect(bridge.updateScriptedStateCalls == [Self.key, Self.key])
    }

    @Test func settlingACatchUnlinksEachCatchOfThatFaction() {
        let bridge = FakePapyrusWorldStateBridgePort()
        let faction = ReferenceKey.generated(7)
        host.fakeScripts.bridge = bridge
        host.fakeWorldState.sortedDirtyKeysResult = [Self.key, .player]
        host.fakeWorldState.componentResult = ScriptedReferenceState(
            forms: [ScriptedStateName.pickpocketCaughtFaction: faction]
        )
        adapter.settlePickpocketCatches(chargedTo: faction, forgotten: false)
        adapter.settlePickpocketCatches(chargedTo: faction, forgotten: true)
        adapter.settlePickpocketCatches(chargedTo: .player, forgotten: true)
        #expect(bridge.updateScriptedStateCalls == [Self.key, .player, Self.key, .player])
    }

    @Test func aPlacedPoisonIsAppliedByThePlayer() {
        #expect(!adapter.applyPlacedPoison(Self.item, on: Self.key))
        host.fakeMagic.applyPlacedPoisonResult = 1
        #expect(adapter.applyPlacedPoison(Self.item, on: Self.key))
        #expect(host.fakeMagic.applyPlacedPoisonCalls.map(\.caster) == [.player, .player])
    }

    @Test func perksModifyValuesAndLabels() throws {
        host.fakePerks.modifiedValueAtOnGivenResult = 1.5
        let subjects = PerkEvaluationSubjects(owner: .player)
        #expect(adapter.perkModified(
            1, at: .modBuyPrices, on: .player, given: (subjects, ConditionContext())
        ) == 1.5)
        #expect(adapter.temperingFactor(for: Self.item) == 1.5)
        #expect(host.fakePerks.modifiedValueAtOnGivenCalls.map(\.entryPoint)
            == [.modBuyPrices, .modTemperingHealth])
        #expect(adapter.perkActivateLabel(for: Self.item) == nil)
        host.fakeStreamer.referenceEntryFormIDResult = try InventoryAdapterFixture.referenceEntry()
        #expect(adapter.perkActivateLabel(for: Self.item) == nil)
        #expect(host.fakePerks.choicesCalls.map(\.entryPoint) == [.setActivateLabel])
        host.fakePerkActivation.promptLabelResult = "Harvest"
        #expect(adapter.perkActivateLabel(for: Self.item) == "Harvest")
    }

    @Test func aTargetTakesTheRuntimeLabel() {
        let labelled = InventoryAdapterFixture.interaction(.harvest)
        host.fakeInventory.labelledResult = labelled
        #expect(adapter.perks.labelled(nil) == nil)
        let target = InventoryAdapterFixture.target(InventoryAdapterFixture.interaction(.take))
        #expect(adapter.perks.labelled(target)?.interaction == labelled)
    }

    @Test func emptyConditionsNeverFail() {
        host.fakeRuntimeState.conditionContextResult = ConditionContext()
        #expect(adapter.failingFunction(
            in: ConditionList(), sourcePlugin: "Skyrim.esm", temperingEnchanted: true
        ) == nil)
        #expect(adapter.failingVendorCondition(
            ConditionList(), sourcePlugin: "Skyrim.esm", merchant: Self.key
        ) == nil)
        #expect(host.fakeRuntimeState.conditionContextCalls.count == 2)
    }
}
