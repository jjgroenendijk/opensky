// A view of the Survival Mode answer and the plugin's globals.

import Foundation
import OpenSkyGameData

nonisolated struct SurvivalModeSnapshot: Equatable, Sendable {
    let answer: SurvivalModeAnswer
    let isForced: Bool
    /// Nil when the Survival Mode plugin is not loaded.
    let globals: SurvivalModeGlobals?

    var lines: [String] {
        let source = isForced ? " (launch option)" : ""
        var lines = ["Answer: \(answer.rawValue)\(source)"]
        guard let globals else {
            return lines + ["Plugin: not loaded"]
        }
        lines.append("Asked: \(globals.prompted ? "yes" : "no")")
        lines.append("Chosen: \(globals.toggle ? "on" : "off")")
        lines.append("Running: \(globals.enabled ? "yes" : "no")")
        lines.append("Choice allowed: \(globals.canBeEnabled ? "yes" : "no")")
        return lines
    }
}

extension SurvivalModeCoordinator {
    var survivalModeSnapshot: SurvivalModeSnapshot {
        SurvivalModeSnapshot(answer: answer, isForced: forcedAnswer != nil, globals: globals)
    }

    func setSurvivalMode(_ on: Bool) {
        store.set(.survivalMode, to: on ? 1 : 0)
    }
}
