import Foundation

// The map, message, movie, perk activation, and survival worlds forward to their ports.

import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyMenuAdapters
import OpenSkyMenusInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import Testing

@MainActor
struct MapMessageWorldTests {
    private let host = MenuHost()
    private static let target = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)

    @Test func withoutRecordsTheMapIsEmpty() {
        let map = MapWorldAdapter(game: host)
        #expect(map.records == nil)
        #expect(map.mapWorldspace == nil)
        #expect(map.mapMarkerSites().isEmpty)
        #expect(map.mapMarkerWorldspaces.isEmpty)
        #expect(map.worldMapLimits == nil)
        #expect(map.mapWorldspaceName == nil)
        #expect(map.playerPosition == nil)
        #expect(map.text(nil) == nil)
        #expect(map.quests.questTargets.isEmpty)
    }

    @Test func mapNoticesReachTheHUDAndMessages() {
        let map = MapWorldAdapter(game: host)
        map.showNotification("Discovered")
        map.showQuestMarkers([.one])
        map.showPlayerSetMarker(.zero)
        map.incrementStat("Locations Discovered")
        map.ask("Travel?", buttons: ["Yes", "No"]) { _ in }
        #expect(host.fakeHud.showNotificationCalls == ["Discovered"])
        #expect(host.fakeHud.updateQuestTargetsCalls == [[.one]])
        #expect(host.fakeHud.updatePlayerSetMarkerCalls == [.zero])
        #expect(host.fakeWorldState.incrementMiscStatCalls.map(\.name) == ["Locations Discovered"])
        #expect(host.fakeMessages.presentChoicesCalls.map(\.buttons) == [["Yes", "No"]])
    }

    @Test func theMapViewIsKeptUntilCleared() {
        let map = MapWorldAdapter(game: host)
        map.setMapView(eye: .one, lookAt: .zero)
        #expect(map.mapViewPose != nil)
        map.clearMapView()
        #expect(map.mapViewPose == nil)
        map.playerSetMarker = nil
        #expect(host.fakeWorldState.resetKindForCalls.map(\.key) == [.player])
    }

    @Test func withoutASessionTravelIsRefused() {
        let map = MapWorldAdapter(game: host)
        host.fakeCombat.combatLoopSnapshotValue = .unavailable
        host.fakeCrime.isPlayerPursued = true
        let context = map.travel.fastTravelContext
        #expect(context.alarmed)
        #expect(!context.inAir)
    }

    @Test func messagesWithoutRecordsAreNotBuilt() {
        let messages = MessageWorldAdapter(
            game: host,
            now: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        #expect(messages.buildMessage(Self.target, arguments: []) == nil)
        #expect(messages.messageEditorIDs.isEmpty)
        #expect(messages.messageKey(editorID: "Help") == nil)
        messages.showHUDNotification("Saved")
        messages.setHUDHelpMessage("Press E")
        messages.answerMessage(token: 1, buttonIndex: 0)
        #expect(host.fakeHud.showNotificationCalls == ["Saved"])
        #expect(host.fakeHud.setHelpMessageCalls == ["Press E"])
    }

    @Test func helpRecordsAreStoredOnThePlayer() {
        let messages = MessageWorldAdapter(
            game: host,
            now: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        #expect(messages.helpMessageRecords.isEmpty)
        messages.helpMessageRecords = [:]
        #expect(host.fakeWorldState.setCalls.map(\.key) == [.player])
    }

    @Test func aCameraShakeStartsFromTheSourceAnchor() {
        let messages = MessageWorldAdapter(
            game: host,
            now: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        host.fakeCinematicWorld.anchorPositionResult = .one
        host.fakeCinematicCamera.startShakeResult = true
        #expect(messages.cameraEffects.shakeCamera(source: Self.target, strength: 1, duration: 2))
        #expect(host.fakeCinematicWorld.anchorPositionCalls == [Self.target])
        #expect(!messages.cameraEffects.forceCameraMode(firstPerson: true))
        #expect(messages.cameraEffects.viewCamera == nil)
    }

    @Test func aRefusedStartupLogoStillContinues() {
        let movies = MovieWorldAdapter(game: host)
        var continued = false
        movies.playStartupLogo { continued = true }
        #expect(continued)
        #expect(host.fakeMovies.playCalls.map(\.fileName) == [MovieWorldAdapter.startupLogo])
        movies.endMovieSound()
        #expect(movies.movieFiles == nil)
    }

    @Test func perkActivationForwardsToStreamerAndPerks() {
        let perks = PerkActivationWorldAdapter(game: host, stage: nil)
        host.fakePerks.choicesResult = []
        #expect(perks.activateChoices(on: Self.target).isEmpty)
        #expect(host.fakePerks.choicesCalls.count == 1)
        #expect(perks.crosshairTarget == nil)
        host.fakeMapWorld.textValueKindResult = "Pick"
        #expect(perks.text(LString.inline("Pick")) == "Pick")
    }

    @Test func survivalGlobalsGoThroughTheRuntimeState() {
        let survival = SurvivalModeWorldAdapter(runtimeState: host.fakeRuntimeState)
        survival.setSurvivalGlobal(1, editorID: "Survival_ModeToggle")
        #expect(host.fakeRuntimeState.setGlobalValueCalls
            .map(\.editorID) == ["Survival_ModeToggle"])
    }
}
