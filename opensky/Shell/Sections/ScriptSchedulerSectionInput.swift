// Control wiring and actions for World > Scripts > Scheduler (issue #278).
// Split from ScriptSchedulerSection.swift so the section's type body stays
// inside the strict-lint limit; the accessibility identifiers set here are the
// UI-test API and are pinned literally in ScriptsPanelTests.
//
// Every action is one provider call, a resync so the pause checkbox and the
// readout agree with the engine immediately, and `finishInteraction()` last so
// keyboard focus returns to the game view.

import AppKit

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
