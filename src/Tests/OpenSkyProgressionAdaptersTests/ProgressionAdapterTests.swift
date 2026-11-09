// The Progression adapters forward each question to the session port that owns the answer.

import OpenSkyCells
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgression
import OpenSkyProgressionAdapters
import OpenSkyProgressionInterface
import OpenSkySessionInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
final class ProgressionHost: ProgressionWorldHost, ProgressionTrainingHost, ProgressionEffectsHost {
    let fakeActorValues = FakeActorValuePort()
    let fakeActorWorld = FakeActorWorldPort()
    let fakeCombat = FakeCombatPort()
    let fakeDialogueWorld = FakeDialogueWorldPort()
    let fakeHUD = FakeHUDPort()
    let fakeInventory = FakeInventoryPort()
    let fakeJournalMenu = FakeJournalMenuPort()
    let fakeMagic = FakeMagicPort()
    let fakeMapWorld = FakeMapWorldPort()
    let fakeMenuWorld = FakeMenuWorldPort()
    let fakePerks = FakePerkPort()
    let fakeRuntimeState = FakeRuntimeStatePort()
    let fakeScripts = FakeScriptPort()
    let fakeStreamer = FakeCellStreamerPort()
    let fakeWorldState = FakeWorldStateStorePort()

    var actorValues: any ActorValuePort {
        fakeActorValues
    }

    var actorWorld: any ActorWorldPort {
        fakeActorWorld
    }

    var combat: any CombatPort {
        fakeCombat
    }

    var dialogueWorld: any DialogueWorldPort {
        fakeDialogueWorld
    }

    var hud: any HUDPort {
        fakeHUD
    }

    var inventory: any InventoryPort {
        fakeInventory
    }

    var journalMenu: any JournalMenuPort {
        fakeJournalMenu
    }

    var magic: any MagicPort {
        fakeMagic
    }

    var mapWorld: any MapWorldPort {
        fakeMapWorld
    }

    var menuWorld: any MenuWorldPort {
        fakeMenuWorld
    }

    var perks: any PerkPort {
        fakePerks
    }

    var runtimeState: any RuntimeStatePort {
        fakeRuntimeState
    }

    var scripts: any ScriptPort {
        fakeScripts
    }

    var streamer: any CellStreamerPort {
        fakeStreamer
    }

    var worldState: any WorldStateStorePort {
        fakeWorldState
    }

    var localizedStringsLoader: (() -> LocalizedStrings)?
    var playerBeastForm = PlayerBeastForm.none
    var worldData: WorldDataStores?
}

@MainActor
struct ProgressionAdapterTests {
    private let host = ProgressionHost()
    private var adapter: ProgressionWorldAdapter {
        ProgressionWorldAdapter(game: host)
    }

    private static let holder = ActorValueHolder.player

    @Test func anActorValueHolderComesFromTheActorWorld() {
        host.fakeActorWorld.actorValueHolderResult = Self.holder
        #expect(adapter.actorValueHolder(for: .player) == Self.holder)
        #expect(host.fakeActorWorld.actorValueHolderCalls == [.player])
    }

    @Test func withoutRuntimesTheAdapterAnswersNothing() {
        #expect(adapter.actorValue(at: 0, on: Self.holder) == nil)
        #expect(adapter.wornArmor(of: .player) == .none)
        #expect(adapter.playerGold() == 0)
        #expect(adapter.perksFromActiveEffects(on: Self.holder).isEmpty)
        #expect(adapter.progressionData() == nil)
        #expect(adapter.perkRuntime(store: WorldStateStore()) == nil)
        #expect(adapter.trainerOffer(for: .player) == nil)
        #expect(!adapter.payTrainer(10, to: .player))
    }

    @Test func thePlayerIdentityComesFromTheMenuWorld() {
        host.fakeMenuWorld.playerNameAndRace = (name: "Prisoner", race: "Nord")
        #expect(adapter.playerIdentity() == (name: "Prisoner", race: "Nord"))
    }

    @Test func theConditionContextComesFromTheRuntimeState() {
        host.fakeRuntimeState.conditionContextResult = ConditionContext()
        _ = adapter.conditionContext()
        #expect(host.fakeRuntimeState.conditionContextCalls == [[]])
    }

    @Test func globalsGoThroughTheRuntimeState() {
        adapter.setGlobalValue(2, editorID: "PlayerIsWerewolf")
        #expect(adapter.globalValue(editorID: "PlayerIsWerewolf") == nil)
        #expect(host.fakeRuntimeState.setGlobalValueCalls.map(\.editorID) == ["PlayerIsWerewolf"])
        #expect(host.fakeRuntimeState.runtimeStateGlobalCalls == ["PlayerIsWerewolf"])
    }

    @Test func theNearestTrainerStartsFromTheNearestActor() {
        #expect(adapter.nearestTrainer() == nil)
        #expect(host.fakeActorWorld.nearestActorValueHolderCallCount == 1)
    }

    @Test func commandsReachTheHUDAndTheStats() {
        adapter.training.run([.showNotification("Trained"), .incrementStat("Training Sessions")])
        #expect(host.fakeHUD.showNotificationCalls == ["Trained"])
        #expect(host.fakeWorldState.incrementMiscStatCalls.map(\.name) == ["Training Sessions"])
    }

    @Test func theBeastTreeFollowsThePlayerForm() {
        host.playerBeastForm = .werewolf
        #expect(adapter.playerBeastTree() == .werewolf)
        host.playerBeastForm = .otherBeast
        #expect(adapter.playerBeastTree() == nil)
    }

    @Test func aQuestStageWithoutAQuestRuntimeChangesNothing() {
        adapter.setPerkQuestStage(10, quest: FormID(0x1), fromPlugin: "Skyrim.esm")
        #expect(host.fakeScripts.bridge == nil)
    }

    @Test func localizedStringsComeFromTheLoader() {
        #expect(adapter.localizedStrings() == nil)
    }
}
