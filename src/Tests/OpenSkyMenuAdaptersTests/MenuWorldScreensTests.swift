import Foundation

// The menu world applies settings and script menu calls; the screens and loading parts read state.

import OpenSkyAgentControl
import OpenSkyCombatInterface
import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyLaunch
import OpenSkyLoading
@testable import OpenSkyMenuAdapters
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySessionTesting
import OpenSkyWorldInterface
import Testing

private final class LayerHolder: MenuLayerHolder {
    func reclaimLayer() {}
}

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

    @Test func aSkillsMenuQuestionGoesToTheMessageBox() {
        let menus = MenuWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
        menus.askSkillsMenuQuestion("Unlock this perk?", buttons: ["Yes", "No"]) { _ in }
        #expect(host.fakeMessages.presentChoicesCalls.map(\.text) == ["Unlock this perk?"])
        #expect(host.fakeMessages.presentChoicesCalls.map(\.buttons) == [["Yes", "No"]])
    }

    /// An owner without a layer stack suspends and restarts for any holder.
    @Test func aPlainLayerOwnerSuspendsAndRestartsForAnyHolder() {
        let hud = FakeHUDPort()
        let holder = LayerHolder()
        hud.suspend(for: holder)
        hud.release(by: holder)
        #expect(hud.suspendCallCount == 1)
        #expect(hud.startCallCount == 1)
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

    @Test func withoutARendererTheTitleBackdropPlacesNothing() {
        let menus = MenuWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
        menus.showTitleBackdrop(true)
        menus.refreshTitleBackdrop()
        host.fakeLoadingScreens.isCovering = true
        menus.refreshTitleBackdrop()
        #expect(menus.titleBackdrop.isWanted)
        #expect(!menus.titleBackdrop.isPlaced)
    }

    @Test func aBackdropWithoutItsFilesIsTheLoadingScenesDarkScreen() throws {
        let renderer = try #require(FakeRendererPort())
        let menus = MenuWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
        menus.showTitleBackdrop(true)
        host.renderer = renderer
        host.fakeLoadingScreens.isCovering = true
        menus.refreshTitleBackdrop()
        #expect(renderer.loadingCovers.isEmpty)
        host.fakeLoadingScreens.isCovering = false
        menus.refreshTitleBackdrop()
        host.menuRecords = FakeMenuRecords()
        menus.showTitleBackdrop(true)
        menus.refreshTitleBackdrop()
        #expect(menus.titleBackdrop.isPlaced)
        #expect(renderer.loadingCovers.count == 2)
        for cover in renderer.loadingCovers {
            #expect(cover.placements?.isEmpty == true)
            #expect(cover.pointLightCount == LoadingScreenScene.lights.count)
            #expect(cover.hasLighting)
        }
        menus.showTitleBackdrop(false)
        #expect(renderer.loadingCovers.last?.placements == nil)
        #expect(!menus.titleBackdrop.isPlaced)
    }

    @Test func theEmptyBackdropLooksThroughTheLoadingScreenCamera() {
        let camera = MenuTitleBackdrop.emptyScene.camera
        #expect(camera?.view.position == LoadingScreenScene.cameraBase)
        #expect(camera?.horizontalFieldOfView == LoadingScreenScene.horizontalFieldOfView(
            LoadingScreenScene.defaultFieldOfView
        ))
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

    @Test func theLoadingCoverStartsAndTakesADragAndTheStick() {
        let loading = LoadingScreenWorldAdapter(
            game: host,
            clock: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        loading.coverSessionStart()
        #expect(host.fakeLoadingScreens.beginFirstLoadCalls.count == 1)
        loading.coverMove(to: .zero)
        #expect(host.fakeLoadingScreens.beginCalls.count == 1)
        loading.route(.move(.left))
        loading.route(.move(.up))
        loading.route(.release(.left))
        #expect(host.fakeLoadingScreens.setStickCalls == [[-1, 0], [-1, 1], [0, 1]])
        loading.route(.pointer(deltaX: 4, deltaY: 2))
        #expect(host.fakeLoadingScreens.dragCalls.isEmpty, "no drag without the button")
        loading.route(.button(.accept))
        loading.route(.pointer(deltaX: 4, deltaY: 2))
        loading.route(MenuPointerEvent(.released, location: .zero, viewSize: .zero))
        loading.route(.pointer(deltaX: 4, deltaY: 2))
        #expect(host.fakeLoadingScreens.dragCalls == [[4, 2]])
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
        #expect(throws: AgentFailure.self) {
            try menus.newGame.startNewGame(LaunchNewGame(start: .normal))
        }
        #expect(host.fakeLoadingScreens.beginLoadCalls.isEmpty)
        menus.teleports.abandonNewGameCover()
        #expect(!host.fakeStreamer.isHeld)
    }
}
