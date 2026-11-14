// A new game at a chosen place: the story skip, the hour, the move, and what
// happens on arrival, over the generated fakes.

import Foundation
import OpenSkyAgentControl
import OpenSkyLaunch
import OpenSkyMenuAdapters
import OpenSkyMenusInterface
import OpenSkySessionTesting
import Testing

@MainActor
struct MenuNewGameTests {
    private let host = MenuHost()
    private let menus: MenuWorldAdapter

    init() {
        menus = MenuWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
        host.fakeAgentWorld.performResult = .done(.success(.null))
        // A refused move ends at once, so the arrival steps run in the same call.
        host.fakeAgentWorld.teleportJobToAgentTeleportTargetError = AgentFailure(
            .invalidArgument, "no cell"
        )
    }

    @Test func aPlaceStartSkipsTheOpeningSetsTheHourAndFinishesOnArrival() throws {
        let plan = LaunchNewGame(
            start: .exterior(worldspace: "Tamriel", x: 6, y: -2), hour: 24,
            weather: "SkyrimClear", story: .helgenRalof, opensRaceMenu: true, items: .thief
        )
        try menus.newGame.startNewGame(plan)
        #expect(host.fakeStoryWorld.skipOpeningQuestCalls == [.ralof])
        #expect(host.fakeStoryWorld.startOpeningQuestCallCount == 0)
        #expect(host.fakeAgentWorld.teleportJobToAgentTeleportTargetCalls
            == [.grid(x: 6, y: -2, worldspace: "Tamriel")])
        let commands = host.fakeAgentWorld.performCalls
        #expect(commands.first == .setTime(hour: 0))
        #expect(commands.dropFirst().first == .weather("SkyrimClear"))
        #expect(commands.count == 2 + LaunchItemPreset.thief.items.count)
        #expect(host.fakeRaceMenu.openCalls == [false])
        #expect(menus.lastNewGame == AgentNewGameRequest(
            start: "exterior:Tamriel:6:-2", hour: 24, weather: "SkyrimClear",
            story: "helgen-ralof", items: "thief", opensRaceMenu: true
        ))
    }

    @Test func aPlainPlaceStartChangesOnlyThePlace() throws {
        #expect(menus.lastNewGame == nil)
        try menus.startNewGame(AgentNewGameRequest(start: "cell:QASmoke", opensRaceMenu: false))
        #expect(host.fakeStoryWorld.skipOpeningQuestCalls.isEmpty)
        #expect(host.fakeAgentWorld.teleportJobToAgentTeleportTargetCalls == [.cell("QASmoke")])
        #expect(host.fakeAgentWorld.performCalls.isEmpty)
        #expect(host.fakeRaceMenu.openCalls.isEmpty)
        #expect(menus.lastNewGame?.start == "cell:QASmoke")
    }

    @Test func theTitleMenusCellStartOpensTheRaceMenu() {
        menus.startNewGame(at: .cell("QASmoke"))
        #expect(host.fakeAgentWorld.teleportJobToAgentTeleportTargetCalls == [.cell("QASmoke")])
        #expect(host.fakeRaceMenu.openCalls == [false])
        #expect(host.fakeStoryWorld.startOpeningQuestCallCount == 0)
    }

    @Test func aRefusedArrivalStepShowsAsANotification() throws {
        host.fakeAgentWorld.performError = AgentFailure(.notFound, "no item 'IronSword'")
        try menus.newGame.startNewGame(LaunchNewGame(
            start: .cell("QASmoke"), story: .helgenHadvar, opensRaceMenu: false, items: .warrior
        ))
        #expect(host.fakeStoryWorld.skipOpeningQuestCalls == [.hadvar])
        #expect(host.fakeHud.showNotificationCalls.contains("New game: no item 'IronSword'"))
    }

    @Test func badTextAndAMissingMarkerAreRefusedBeforeAnythingChanges() {
        #expect(throws: AgentFailure.self) {
            try menus.startNewGame(AgentNewGameRequest(start: "cell:QASmoke", story: "done"))
        }
        #expect(throws: AgentFailure.self) {
            try menus.newGame.startNewGame(LaunchNewGame(
                start: .marker(worldspace: "Tamriel", plugin: "Skyrim.esm", objectID: 0x900)
            ))
        }
        #expect(host.fakeAgentWorld.teleportJobToAgentTeleportTargetCalls.isEmpty)
        #expect(host.fakeAgentWorld.teleportJobToSavePlayerPlaceCalls.isEmpty)
        #expect(menus.lastNewGame == nil)
    }

    @Test func theArrivalStepsAreTheWeatherThenTheItems() {
        let plan = LaunchNewGame(start: .cell("QASmoke"), weather: "SkyrimClear", items: .mage)
        let steps = MenuWorldNewGameAdapter.arrivalSteps(of: plan)
        #expect(steps.first == .weather("SkyrimClear"))
        #expect(steps.count == 1 + LaunchItemPreset.mage.items.count)
        #expect(MenuWorldNewGameAdapter.arrivalSteps(of: LaunchNewGame(start: .cell("X"))).isEmpty)
    }
}
