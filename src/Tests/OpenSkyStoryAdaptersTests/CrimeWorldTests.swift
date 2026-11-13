// The crime world runs crime commands and reads cells, items, and names from the ports.

import OpenSkyActorsInterface
import OpenSkyCrimeInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkySessionTesting
import OpenSkyStoryAdapters
import OpenSkyWorldInterface
import Testing

@MainActor
struct CrimeWorldTests {
    private let host = StoryHost()
    private let adapter: CrimeWorldAdapter
    private static let faction = ReferenceKey.plugin(name: "base.esm", objectID: 0x30)
    private static let guardKey = ReferenceKey.plugin(name: "base.esm", objectID: 0x31)
    private static let cell = CellSceneLocation.interior(FormID(0x50))

    init() {
        adapter = CrimeWorldAdapter(game: host)
    }

    @Test func noticesStatsAndPickpocketsReachTheirPorts() {
        adapter.run([
            .showNotice("Caught"),
            .incrementStat("Bounties", by: 2),
            .settlePickpocketCatches(Self.faction, forgotten: true),
            .speakTrespassWarning(by: Self.guardKey),
            .stoleFromFaction(Self.faction, value: 10, witnessed: false)
        ])
        #expect(host.fakeHud.showNotificationCalls == ["Caught"])
        #expect(host.fakeWorldState.incrementMiscStatCalls.map(\.name) == ["Bounties"])
        #expect(host.fakeWorldState.incrementMiscStatCalls.map(\.amount) == [2])
        #expect(host.fakeInventoryWorld.settlePickpocketCatchesCalls
            .map(\.faction) == [Self.faction])
        #expect(host.fakeStoryWorld.sayTopicCalls.map(\.speaker) == [Self.guardKey])
        #expect(host.fakeStoryWorld.sayTopicCalls.map(\.lookAt) == [.player])
    }

    @Test func aRaisedStatOnlyGrows() {
        host.fakeWorldState.miscStatsValue = MiscStatsState(values: ["Days Jailed": 2])
        adapter.run([.raiseStat("Days Jailed", to: 5), .raiseStat("Days Jailed", to: 1)])
        #expect(host.fakeWorldState.incrementMiscStatCalls.map(\.amount) == [3])
    }

    @Test func cellsWithoutAResidentSceneHaveNoOwnerOrLink() {
        host.fakeStreamer.currentCellLocation = Self.cell
        #expect(adapter.currentCellLocation == Self.cell)
        #expect(adapter.cellOwnership(at: Self.cell) == nil)
        #expect(adapter.cellTrespassFlags(at: Self.cell) == CellTrespassFlags())
        #expect(adapter.cellLocationLink(at: Self.cell) == nil)
        #expect(host.fakeStreamer.residentSceneCalls == [Self.cell, Self.cell, Self.cell])
        #expect(adapter.references != nil)
    }

    @Test func itemsAndNamesComeFromTheirPorts() {
        host.fakeDialogueWorld.speakerLabelResult = "Guard"
        host.fakeInventory.readoutResult = []
        #expect(adapter.actorName(Self.guardKey) == "Guard")
        #expect(host.fakeDialogueWorld.speakerLabelCalls == [Self.guardKey])
        #expect(adapter.itemValue(of: FormID(0x40)) == 0)
        #expect(adapter.inventory == nil)
        #expect(adapter.crosshairInteraction == nil)
        #expect(adapter.stolenPlayerStacks().isEmpty)
        #expect(adapter.vendor(faction: Self.faction) == nil)
        #expect(adapter.vendor(of: Self.guardKey) == nil)
        #expect(adapter.targetOwnership() == nil)
        #expect(host.fakeInventory.itemPanels.targetOwnershipCallCount == 1)
    }

    @Test func witnessesNeedASession() {
        _ = adapter.witnesses()
        #expect(host.gameSession == nil)
    }

    @Test func factionCallsReachTheFactionPort() {
        host.fakeFactions.joinResult = true
        host.fakeFactions.leaveResult = true
        #expect(!adapter.hasFactionData)
        #expect(adapter.factionMemberships(of: Self.guardKey) == nil)
        #expect(adapter.socialProfile(of: Self.guardKey) == nil)
        #expect(adapter.joinFaction(Self.faction, actor: Self.guardKey, rank: 2))
        #expect(adapter.leaveFaction(Self.faction, actor: Self.guardKey))
        #expect(host.fakeFactions.membershipsCalls == [Self.guardKey])
        #expect(host.fakeFactions.joinCalls.map(\.rank) == [2])
        #expect(host.fakeFactions.leaveCalls.map(\.faction) == [Self.faction])
    }
}
