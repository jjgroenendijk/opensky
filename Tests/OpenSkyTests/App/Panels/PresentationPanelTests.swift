// World > Kill Cam, World > Loading Screens, and HUD & Interaction > Messages
// with the provider fake: pinned ids, visible frames, and each control driving
// the fake.

import AppKit
@testable import OpenSky
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyMenus
@testable import OpenSkyWorld
import Testing

@MainActor
struct PresentationPanelTests {
    private func tap(_ control: NSControl) {
        control.sendAction(control.action, to: control.target)
    }

    private func worldPanel(_ provider: FakeWorldProviders) -> WorldPanelViewController {
        let panel = WorldPanelViewController()
        panel.loadViewIfNeeded()
        panel.cinematicProvider = provider
        panel.loadingProvider = provider
        return panel
    }

    private func messagesSection(_ provider: FakeWorldProviders) -> MessagesSection {
        let panel = HUDInteractionPanelViewController()
        panel.loadViewIfNeeded()
        panel.messageProvider = provider
        return panel.messagesSection
    }

    private static func available() -> FakeWorldProviders {
        let provider = FakeWorldProviders()
        provider.presentationState.cinematic.isAvailable = true
        provider.presentationState.cinematic.shotNames = ["KillCamBow", "KillCamSword"]
        provider.presentationState.loading.isAvailable = true
        provider.presentationState.loading.screenNames = ["LoadScreenDragon"]
        provider.presentationState.loading.passing = ["LoadScreenDragon"]
        provider.presentationState.messages.isAvailable = true
        provider.presentationState.messages.messageNames = ["HelpJump"]
        return provider
    }

    @Test func accessibilityIdentifiersArePinned() {
        let provider = FakeWorldProviders()
        let panel = worldPanel(provider)
        let cinematic = panel.cinematicSection
        let loading = panel.loadingSection
        let messages = messagesSection(provider)
        #expect(cinematic.sectionIdentifier == "killCam")
        #expect(loading.sectionIdentifier == "loadingScreens")
        #expect(messages.sectionIdentifier == "messages")
        let controls: [(NSView, String)] = [
            (cinematic.shotControl, "CameraShotControl"),
            (cinematic.playShotControl, "CameraShotPlayControl"),
            (cinematic.killCamControl, "KillCamPlayControl"),
            (cinematic.stopControl, "CinematicStopControl"),
            (cinematic.shakeControl, "CameraShakeControl"),
            (cinematic.enabledControl, "KillCamEnabledControl"),
            (loading.screenControl, "LoadingScreenControl"),
            (loading.forceControl, "LoadingScreenForceControl"),
            (loading.releaseControl, "LoadingScreenReleaseControl"),
            (loading.enabledControl, "LoadingScreenEnabledControl"),
            (messages.messageControl, "MessageSelectControl"),
            (messages.notifyControl, "MessageNotifyControl"),
            (messages.boxControl, "MessageBoxControl"),
            (messages.resetHelpControl, "MessageResetHelpControl")
        ]
        for (control, identifier) in controls {
            #expect(control.accessibilityIdentifier() == identifier)
        }
    }

    @Test func killCamControlsHaveVisibleFrames() throws {
        let panel = worldPanel(Self.available())
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 320, height: 2400)
        panel.view.layoutSubtreeIfNeeded()
        let section = panel.cinematicSection
        for control in [section.shotControl, section.playShotControl, section.enabledControl] {
            let name = control.accessibilityIdentifier()
            #expect(!control.isHidden, "\(name) hidden")
            #expect(control.frame.height > 0, "\(name) frame=\(control.frame)")
            let documentFrame = control.convert(control.bounds, to: scrollView.documentView)
            #expect(scrollView.documentView?.bounds.intersects(documentFrame) == true)
        }
    }

    @Test func killCamControlsDriveTheProvider() {
        let provider = Self.available()
        let section = worldPanel(provider).cinematicSection
        section.refreshReadout()
        #expect(section.shotControl.objectValues as? [String] == ["KillCamBow", "KillCamSword"])
        section.shotControl.stringValue = "KillCamBow"
        tap(section.playShotControl)
        tap(section.killCamControl)
        tap(section.stopControl)
        tap(section.shakeControl)
        section.enabledControl.state = .off
        tap(section.enabledControl)
        #expect(provider.presentationState.playedShots == ["KillCamBow"])
        #expect(provider.presentationState.killCams == 1)
        #expect(provider.presentationState.stops == 1)
        #expect(provider.presentationState.shakes == 1)
        #expect(!provider.killCamsEnabled)
        #expect(section.readout.contains("Shot: none"))
    }

    @Test func loadingControlsForceReleaseAndToggle() {
        let provider = Self.available()
        let section = worldPanel(provider).loadingSection
        section.refreshReadout()
        #expect(!section.releaseControl.isEnabled)
        section.screenControl.stringValue = "LoadScreenDragon"
        tap(section.forceControl)
        section.refreshReadout()
        #expect(provider.presentationState.forcedScreens == ["LoadScreenDragon"])
        #expect(section.releaseControl.isEnabled)
        tap(section.releaseControl)
        section.enabledControl.state = .off
        tap(section.enabledControl)
        #expect(provider.presentationState.releases == 1)
        #expect(!provider.loadingScreensEnabled)
        #expect(section.readout.contains("Pass here: 1 of 1"))
    }

    @Test func messageControlsShowEitherWayAndResetHelp() {
        let provider = Self.available()
        let section = messagesSection(provider)
        section.refreshReadout()
        section.messageControl.stringValue = "HelpJump"
        tap(section.notifyControl)
        tap(section.boxControl)
        tap(section.resetHelpControl)
        #expect(provider.presentationState.shownMessages.map(\.0) == ["HelpJump", "HelpJump"])
        #expect(provider.presentationState.shownMessages.map(\.1) == [false, true])
        #expect(provider.presentationState.helpResets == 1)
        #expect(section.readout.contains("Notifications: 0 shown, 0 waiting"))
    }

    @Test func combatLoopReadoutShowsTheSelectedActorsStyle() {
        let provider = FakeWorldProviders()
        let section = CombatPhysicsPanelViewController().loopSection
        section.loadViewIfNeeded()
        section.provider = provider
        section.refreshReadout()
        #expect(section.readout.contains("Style: none"))
        let tuning = CombatStyleTuning(
            offensiveMultiplier: 1, defensiveMultiplier: 0.5, meleeScoreMultiplier: 1,
            magicScoreMultiplier: 1, name: "csTestBrute"
        )
        provider.presentationState.combatStyle = CombatStyleReadout(tuning: tuning, base: .standard)
        section.refreshReadout()
        #expect(section.readout.contains("Style: csTestBrute"))
        #expect(section.readout.contains("Attack gap: 0.80 s (base 1.60)"))
    }
}
