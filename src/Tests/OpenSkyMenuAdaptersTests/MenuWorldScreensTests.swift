import Foundation

// The menu world applies settings and script menu calls; the screens and loading parts read state.

import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyLaunch
import OpenSkyMenuAdapters
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import Testing

@MainActor
struct MenuWorldScreensTests {
    private let host = MenuHost()
    private static let marker = ReferenceKey.plugin(name: "base.esm", objectID: 0x30)
    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x31)

    @Test func audioSettingsReachTheAudioPort() {
        let menus = MenuWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
        menus.applyAudioEnabled(false)
        menus.applyMasterVolume(0.5)
        menus.applyCategoryVolume(0.2, soundCategoryEditorID: "no such category")
        #expect(!host.fakeAudio.audioEnabled)
        #expect(host.fakeAudio.audioMasterVolume == 0.5)
        #expect(host.fakeAudio.setAudioVolumeCalls.isEmpty)
    }

    @Test func mapCallsGoThroughTheMapMenu() {
        let menus = MenuWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
        host.fakeMapMenu.selectResult = true
        host.fakeMapMenu.canTravelResult = true
        #expect(menus.fastTravel(to: Self.marker))
        #expect(menus.canFastTravel(to: Self.marker))
        menus.setFastTravelEnabled(true)
        #expect(menus.isFastTravelEnabled)
        menus.addToMap(Self.marker, allowFastTravel: true)
        menus.setHUDCartMode(true)
        menus.showRaceMenu(limited: true)
        #expect(host.fakeMapMenu.travelToSelectedCallCount == 1)
        #expect(host.fakeMapMenu.addToMapCalls.map(\.key) == [Self.marker])
        #expect(host.fakeHud.setCartModeCalls == [true])
        #expect(host.fakeRaceMenu.openCalls == [true])
    }

    @Test func anUnselectableMarkerIsNotTravelledTo() {
        let menus = MenuWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
        #expect(!menus.fastTravel(to: Self.marker))
        #expect(host.fakeMapMenu.travelToSelectedCallCount == 0)
    }

    @Test func onlyThePlayerChangesRace() {
        let menus = MenuWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
        #expect(!menus.setRace(of: Self.actor, to: FormID(0x13746)))
        #expect(menus.race(of: Self.actor) == nil)
        #expect(menus.race(of: .player) == nil)
        #expect(menus.sex(ofBase: FormID(0x40)) == nil)
    }

    @Test func aSleepRefusalComesFromTheCrimePort() {
        let screens = MenuScreensWorldAdapter(game: host)
        host.fakeCombat.combatLoopSnapshotValue = .unavailable
        host.fakeCrime.isPlayerPursued = true
        host.fakeMapWorld.settingTextsResult = GameSettingTexts<RestText>.vanilla
        #expect(screens.restRefusal(sleeping: true, bed: nil) != nil)
        host.fakeCrime.isPlayerPursued = false
        #expect(screens.restRefusal(sleeping: false, bed: nil) == nil)
        #expect(screens.gameDateText == nil)
        screens.passTime(hours: 2, sleeping: true)
        #expect(host.fakeScripts.reportSleepCalls.isEmpty)
    }

    @Test func guidesReadMessagesAndTrainers() {
        let screens = MenuScreensWorldAdapter(game: host)
        host.fakeMessageWorld.messageEditorIDs = ["HelpCombatLong", "Other"]
        #expect(screens.guides.helpTopicEditorIDs == ["HelpCombatLong"])
        #expect(screens.guides.helpTopic("HelpCombatLong") == nil)
        #expect(screens.guides.nearestTrainer == nil)
        #expect(screens.guides.train(with: Self.actor) == "No trainer")
        #expect(screens.guides.mapScreenPoint(.zero) == nil)
        screens.showHUDNotification("Rested")
        #expect(host.fakeHud.showNotificationCalls == ["Rested"])
    }

    @Test func theLoadingCoverStartsAndTurns() {
        let loading = LoadingScreenWorldAdapter(
            game: host,
            clock: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        loading.coverSessionStart()
        #expect(host.fakeLoadingScreens.beginLoadCalls.count == 1)
        loading.coverMove(to: .zero)
        #expect(host.fakeLoadingScreens.beginCalls.count == 1)
        loading.route(.move(.left))
        #expect(host.fakeLoadingScreens.turnCalls
            .map(\.degrees) == [-LoadingScreenWorldAdapter.turnDegreesPerKey])
    }

    @Test func pausingTheLoadingCoverPresentsItsMenu() {
        let loading = LoadingScreenWorldAdapter(
            game: host,
            clock: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        loading.setLoadingPaused(true)
        loading.setLoadingPaused(false)
        #expect(host.fakeMenuMode.presentCalls.count == 1)
        #expect(host.fakeMenuMode.dismissCalls.count == 1)
        loading.presentLoadingCover(nil)
        #expect(loading.presentationRecords == nil)
        #expect(!loading.isMovieLoaded)
    }

    @Test func teleportsCoverAndReportFailures() {
        let menus = MenuWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
        menus.teleports.startPlayer(at: .normal)
        #expect(host.fakeLoadingScreens.beginLoadCalls.isEmpty)
        menus.teleports.abandonNewGameCover()
        #expect(!host.fakeStreamer.isHeld)
    }
}
