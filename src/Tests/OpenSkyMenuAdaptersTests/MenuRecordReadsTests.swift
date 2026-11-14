import Foundation

// The Menu adapters read their records through the port and their time from the clock.

import OpenSkyAgentControl
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyLaunch
import OpenSkyMenuAdapters
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkySessionTesting
import Testing

@MainActor
struct MenuRecordReadsTests {
    private typealias Fixture = ESMFixture
    private let host = MenuHost()
    private let records = FakeMenuRecords()
    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x31)

    private func menus(at seconds: Double = 0) -> MenuWorldAdapter {
        MenuWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: seconds) })
    }

    @Test func withoutRecordsTheReadsFallBack() {
        let map = MapWorldAdapter(game: host)
        #expect(map.settingTexts(SkillsMenuText.self) == .vanilla)
        let messages = MessageWorldAdapter(game: host, stage: nil, now: { Date() })
        #expect(messages.systemMenuTopics(.help).isEmpty)
        #expect(menus().titleLighting == nil)
        #expect(menus().skillsRace.perkSkySource == nil)
        let loading = LoadingScreenWorldAdapter(game: host, stage: nil, clock: { Date() })
        #expect(loading.cameraPathLoader() == nil)
    }

    @Test func recordsGiveTheFileReads() {
        host.menuRecords = records
        #expect(menus().skillsRace.perkSkySource != nil)
        let loading = LoadingScreenWorldAdapter(game: host, stage: nil, clock: { Date() })
        #expect(loading.cameraPathLoader() != nil)
        #expect(menus().scriptMenus.leveledBase(of: Self.actor, base: FormID(0x40)) == FormID(0x40))
    }

    @Test func aFailedMoveLiftsItsCoverOnTheClock() throws {
        host.fakeAgentWorld.teleportJobToAgentTeleportTargetError = AgentFailure(
            .invalidArgument, "no cell"
        )
        try menus(at: 7).newGame.startNewGame(
            LaunchNewGame(start: .cell("NoSuchCell"), opensRaceMenu: false)
        )
        #expect(host.fakeLoadingScreens.beginLoadCalls == [7])
        #expect(host.fakeLoadingScreens.loadFinishedCalls == [7])
        #expect(host.fakeHud.showNotificationCalls == ["Move: no cell"])
    }

    @Test func messagesTickOnTheWallClock() {
        MessageWorldAdapter.tick(host, now: { Date(timeIntervalSinceReferenceDate: 5) })
        #expect(host.fakeMessages.tickCalls == [5])
        #expect(host.fakeSubtitles.advanceCalls == [5])
    }

    @Test func aMessageOwnedByAQuestBuildsWithoutQuests() throws {
        let owner = Fixture.recordBytes("MESG", formID: 0x51, fields: [
            ("DESC", Fixture.zstring("Owner"))
        ])
        let message = Fixture.recordBytes("MESG", formID: 0x50, fields: [
            ("DESC", Fixture.zstring("Hello")), ("QNAM", Fixture.u32(0x51))
        ])
        records.presentationRecords = try PresentationRecordStore(
            plugins: [("base.esm", Fixture.plugin(records: [owner, message]))]
        )
        host.menuRecords = records
        host.fakeRuntimeState.conditionContextResult = ConditionContext()
        let messages = MessageWorldAdapter(game: host, now: { Date() })
        let built = messages.buildMessage(.plugin(name: "base.esm", objectID: 0x50), arguments: [])
        #expect(built != nil)
    }
}
