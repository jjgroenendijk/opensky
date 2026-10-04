// Kill cam, loading screen, message, and combat style part of the shared panel fake.

import Foundation
import OpenSkyCombat
import OpenSkyMenus
@testable import OpenSkyWorld

/// What the Kill Cam, Loading Screens, and Messages sections read, and what they asked for.
final class FakePresentationState {
    var cinematic = CinematicCameraSnapshot()
    var loading = LoadingScreenSnapshot()
    var messages = MessageControlSnapshot()
    var combatStyle: CombatStyleReadout?
    var playedShots: [String] = []
    var killCams = 0
    var stops = 0
    var shakes = 0
    var forcedScreens: [String] = []
    var releases = 0
    var shownMessages: [(String, Bool)] = []
    var helpResets = 0
}

extension FakeWorldProviders {
    var cinematicSnapshot: CinematicCameraSnapshot {
        presentationState.cinematic
    }

    var killCamsEnabled: Bool {
        get { presentationState.cinematic.killCamsEnabled }
        set { presentationState.cinematic.killCamsEnabled = newValue }
    }

    func playCameraShot(editorID: String) {
        presentationState.playedShots.append(editorID)
    }

    func playKillCamOnSelected() {
        presentationState.killCams += 1
    }

    func stopCinematicCamera() {
        presentationState.stops += 1
    }

    func shakeCamera() {
        presentationState.shakes += 1
    }
}

extension FakeWorldProviders {
    var loadingScreenSnapshot: LoadingScreenSnapshot {
        presentationState.loading
    }

    var loadingScreensEnabled: Bool {
        get { presentationState.loading.isEnabled }
        set { presentationState.loading.isEnabled = newValue }
    }

    func forceLoadingScreen(editorID: String) {
        presentationState.forcedScreens.append(editorID)
        presentationState.loading.isForced = true
    }

    func releaseLoadingScreen() {
        presentationState.releases += 1
        presentationState.loading.isForced = false
    }
}

extension FakeWorldProviders {
    var messageSnapshot: MessageControlSnapshot {
        presentationState.messages
    }

    func showMessage(editorID: String, asBox: Bool) {
        presentationState.shownMessages.append((editorID, asBox))
    }

    func resetHelpMessages() {
        presentationState.helpResets += 1
    }
}
