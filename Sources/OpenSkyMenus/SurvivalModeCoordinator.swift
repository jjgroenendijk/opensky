// Keeps the Survival Mode settings and the plugin's globals in step. Before the
// scripts run each frame it answers an open prompt, or copies a choice the
// session made back into the setting. See docs/engine/survival-mode.md.

import Foundation
import OpenSkyGameData

/// The plugin's globals in the running session. The app answers it.
public protocol SurvivalModeWorld: AnyObject {
    /// Nil when no loaded plugin defines the global.
    func survivalGlobal(_ editorID: String) -> Float?
    func setSurvivalGlobal(_ value: Float, editorID: String)
}

public final class SurvivalModeCoordinator {
    public let store: PlayerSettingsStore
    private weak let world: SurvivalModeWorld?
    /// From `OPENSKY_SURVIVAL_MODE`; wins over the settings for this run.
    public var forcedAnswer: SurvivalModeAnswer?
    public private(set) var lastStep = SurvivalModeCore.Step.none

    public init(
        store: PlayerSettingsStore, world: SurvivalModeWorld?,
        forcedAnswer: SurvivalModeAnswer? = SurvivalModeAnswer.forced()
    ) {
        self.store = store
        self.world = world
        self.forcedAnswer = forcedAnswer
        store.observe { [weak self] id in
            if id == .survivalMode {
                self?.applySetting()
            }
        }
    }

    public var answer: SurvivalModeAnswer {
        forcedAnswer ?? SurvivalModeCore.answer(
            ask: store.bool(.survivalModeAsk), setting: store.bool(.survivalMode)
        )
    }

    public var globals: SurvivalModeGlobals? {
        guard
            let world,
            let prompted = world.survivalGlobal(SurvivalModeCore.promptedEditorID),
            let toggle = world.survivalGlobal(SurvivalModeCore.toggleEditorID)
        else { return nil }
        return SurvivalModeGlobals(
            prompted: prompted != 0, toggle: toggle != 0,
            enabled: world.survivalGlobal(SurvivalModeCore.enabledEditorID) ?? 0 != 0,
            canBeEnabled: world.survivalGlobal(SurvivalModeCore.canBeEnabledEditorID) ?? 0 != 0
        )
    }

    public func tick() {
        guard let globals else { return }
        let step = SurvivalModeCore.step(
            globals: globals, answer: answer, setting: store.bool(.survivalMode)
        )
        switch step {
        case .none:
            return
        case let .answer(on):
            write(on)
        case let .mirror(on):
            // A launch option lasts one run, so its session leaves the saved setting alone.
            guard forcedAnswer == nil else { return }
            store.set(.survivalMode, to: on ? 1 : 0)
        }
        lastStep = step
    }

    /// A choice made in the settings answers the prompt, as the game's Gameplay toggle does.
    private func applySetting() {
        guard let globals else { return }
        let on = store.bool(.survivalMode)
        if globals.toggle != on || !globals.prompted {
            write(on)
        }
    }

    private func write(_ on: Bool) {
        world?.setSurvivalGlobal(on ? 1 : 0, editorID: SurvivalModeCore.toggleEditorID)
        world?.setSurvivalGlobal(1, editorID: SurvivalModeCore.promptedEditorID)
    }
}
