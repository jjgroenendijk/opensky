// The sidebar's view of the Survival Mode answer and the plugin's globals.

import Foundation
import OpenSkyGameData

nonisolated public struct SurvivalModeSnapshot: Equatable, Sendable {
    public let answer: SurvivalModeAnswer
    public let isForced: Bool
    /// Nil when the Survival Mode plugin is not loaded.
    public let globals: SurvivalModeGlobals?

    public init(answer: SurvivalModeAnswer, isForced: Bool, globals: SurvivalModeGlobals?) {
        self.answer = answer
        self.isForced = isForced
        self.globals = globals
    }

    public var lines: [String] {
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

public protocol SurvivalModeControlProviding: AnyObject {
    var survivalModeSnapshot: SurvivalModeSnapshot { get }
    func setSurvivalMode(_ on: Bool)
    func setSurvivalModeAsk(_ ask: Bool)
}

extension SurvivalModeCoordinator: SurvivalModeControlProviding {
    public var survivalModeSnapshot: SurvivalModeSnapshot {
        SurvivalModeSnapshot(answer: answer, isForced: forcedAnswer != nil, globals: globals)
    }

    public func setSurvivalMode(_ on: Bool) {
        store.set(.survivalMode, to: on ? 1 : 0)
    }

    public func setSurvivalModeAsk(_ ask: Bool) {
        store.set(.survivalModeAsk, to: ask ? 1 : 0)
    }
}
