// Control wiring and actions for World > Scripts > Scheduler, split out for the
// type-body limit. ScriptsPanelTests pins the accessibility ids. Each action is
// one provider call, a resync, then `finishInteraction()` to refocus the game.

import AppKit
import OpenSkyScripting

extension ScriptSchedulerSection {
    /// Wires target, action, and identifier for every control. Called once from
    /// `makeContentViews()`.
    func configureControls() {
        PanelComponents.configureCheckbox(
            pauseControl, target: self, action: #selector(pauseToggled),
            identifier: "ScriptPauseControl"
        )
        PanelComponents.configureButton(
            stepControl, target: self, action: #selector(stepPressed),
            identifier: "ScriptStepControl"
        )
        PanelComponents.configureButton(
            burstControl, target: self, action: #selector(burstPressed),
            identifier: "ScriptBurstControl"
        )
    }

    @objc func pauseToggled() {
        provider?.setScriptsPaused(pauseControl.state == .on)
        syncControls()
        finishInteraction()
    }

    @objc func stepPressed() {
        provider?.stepScripts(ticks: 1)
        syncControls()
        finishInteraction()
    }

    @objc func burstPressed() {
        provider?.stepScripts(ticks: ScriptSchedulerSection.burstTicks)
        syncControls()
        finishInteraction()
    }
}
