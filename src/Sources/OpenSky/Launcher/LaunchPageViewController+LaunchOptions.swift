// The Launch page's launch options: resume the newest save, skip the main menu,
// full screen, and the startup logo. `LaunchPlan` holds the rule; this file only shows it.

import AppKit
import OpenSkyGameData
import OpenSkyLaunch
import OpenSkySave

extension LaunchPageViewController {
    func makeLaunchOptionsGroup() -> NSView {
        let boxes = [
            (resumeControl, "LaunchResumeControl", "Play loads the newest save"),
            (
                skipMainMenuControl,
                "LaunchSkipMainMenuControl",
                "Load the save without the main menu"
            ),
            (fullScreenControl, "LaunchFullScreenControl", "Play opens full screen"),
            (
                startupLogoControl,
                "LaunchStartupLogoControl",
                "The logo movie before the main menu; a key skips it"
            )
        ]
        for (box, identifier, toolTip) in boxes {
            PanelComponents.configureCheckbox(
                box, target: self, action: #selector(launchOptionChanged), identifier: identifier
            )
            box.toolTip = toolTip
        }
        refreshLaunchOptions()
        return layout.group("Launch options", [
            layout.toggle(resumeControl), skipMainMenuRow, layout.toggle(fullScreenControl),
            layout.toggle(startupLogoControl)
        ])
    }

    func refreshLaunchOptions() {
        let settings = SettingsStore.shared
        resumeControl.state = settings
            .value(LaunchPreferences.resumesLatestSaveSetting) ? .on : .off
        skipMainMenuControl.state = settings.value(LaunchPreferences.skipsMainMenuSetting)
            ? .on : .off
        let store = context.playerSettings()
        fullScreenControl.state = store.bool(.fullScreen) ? .on : .off
        startupLogoControl.state = store.bool(.startupLogo) ? .on : .off
        skipMainMenuRow.isHidden = resumeControl.state == .off
        refreshPlay()
    }

    /// Reads the save list off the main actor each time the page shows.
    func refreshContinue() {
        continueCheck?.cancel()
        continueCheck = Task { [weak self] in
            let offer = await OpenSkySaveStore.continueOffer()
            guard !Task.isCancelled else { return }
            self?.show(offer)
        }
    }

    func show(_ offer: ContinueOffer) {
        continueOffer = offer
        let date = offer.date.map { date in
            ", " + date.formatted(date: .abbreviated, time: .shortened)
        } ?? ""
        latestSave = "\(offer.title)\(date)"
        refreshPlay()
    }

    var launchPlan: LaunchPlan {
        LaunchPlan(
            resumesLatestSave: resumeControl.state == .on,
            skipsMainMenu: skipMainMenuControl.state == .on,
            newestSlot: continueOffer.isEnabled ? continueOffer.slot : nil,
            start: validStart ?? .normal
        )
    }

    /// One line under Play that says what it will do.
    var playSummaryText: String {
        let resumes = resumeControl.state == .on
        let hasSave = continueOffer.isEnabled
        switch launchPlan {
        case .resume:
            return "Loads \(latestSave)"
        case .mainMenu where resumes && hasSave:
            return "Opens the main menu; Continue loads \(latestSave)"
        case .mainMenu:
            return resumes ? "No save to resume: opens the main menu" : "Opens the main menu"
        case let .newGame(start):
            return (resumes ? "No save to resume: " : "")
                + "Starts a new game in \(placeName(of: start))"
        }
    }

    @objc private func launchOptionChanged() {
        let settings = SettingsStore.shared
        settings.set(resumeControl.state == .on, for: LaunchPreferences.resumesLatestSaveSetting)
        settings.set(skipMainMenuControl.state == .on, for: LaunchPreferences.skipsMainMenuSetting)
        let store = context.playerSettings()
        store.set(.fullScreen, to: fullScreenControl.state == .on ? 1 : 0)
        store.set(.startupLogo, to: startupLogoControl.state == .on ? 1 : 0)
        refreshLaunchOptions()
    }
}
