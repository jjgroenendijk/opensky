// The Launch page's New game group: where a new game starts, the startup logo, and
// the Survival Mode answer, so the plugin's prompt does not stop a new game unless the
// player asks for it.

import AppKit
import OpenSkyGameData
import OpenSkyLaunch

extension LaunchPageViewController {
    func makeNewGameGroup() -> NSView {
        PanelComponents.configureCheckbox(
            survivalModeControl, target: self, action: #selector(survivalModeChanged),
            identifier: "LaunchSurvivalModeControl"
        )
        survivalModeControl.toolTip = "Hunger, fatigue, and cold; change it later in Gameplay"
        PanelComponents.configureCheckbox(
            survivalModeAskControl, target: self, action: #selector(survivalModeChanged),
            identifier: "LaunchSurvivalModeAskControl"
        )
        survivalModeAskControl.toolTip =
            "The game asks in a new game; the Survival Mode box above is then ignored"
        PanelComponents.configureCheckbox(
            startupLogoControl, target: self, action: #selector(startupLogoChanged),
            identifier: "LaunchStartupLogoControl"
        )
        startupLogoControl.toolTip = "The logo movie before the main menu; a key skips it"
        refreshNewGame()
        return layout.group("New game", [
            layout.row("Starts at", startPopUp)
        ] + startOptions.rows + [
            startReasonLabel, layout.toggle(startupLogoControl), layout.toggle(survivalModeControl),
            layout.toggle(survivalModeAskControl)
        ])
    }

    func refreshNewGame() {
        let store = context.playerSettings()
        let ask = store.bool(.survivalModeAsk)
        survivalModeAskControl.state = ask ? .on : .off
        survivalModeControl.state = store.bool(.survivalMode) ? .on : .off
        survivalModeControl.isEnabled = !ask
        startupLogoControl.state = store.bool(.startupLogo) ? .on : .off
    }

    @objc private func startupLogoChanged() {
        context.playerSettings().set(.startupLogo, to: startupLogoControl.state == .on ? 1 : 0)
    }

    @objc private func survivalModeChanged() {
        let store = context.playerSettings()
        store.set(.survivalModeAsk, to: survivalModeAskControl.state == .on ? 1 : 0)
        store.set(.survivalMode, to: survivalModeControl.state == .on ? 1 : 0)
        refreshNewGame()
    }

    /// Shows why Play is off for a new game, if it is.
    func refreshStart() {
        for row in startOptions.rows {
            row.isHidden = start == .normal
        }
        var reason: String?
        if validStart == nil {
            reason = context.isLoadingStartPlaces ? Self.readingTitle : nil
        } else if start != .normal {
            reason = startOptions.problem?.reason
        }
        startReasonLabel.stringValue = reason.map { "Play is off: \($0)" } ?? ""
        startReasonLabel.toolTip = startReasonLabel.stringValue
        startReasonLabel.isHidden = reason == nil
        refreshPlay()
    }
}
