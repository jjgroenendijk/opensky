// Value types for the Papyrus world runtime: instance identity and state, queued
// events, and the per-tick budget and report.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// World-side identity of one attached script instance: the reference the
/// script is attached to plus its lowercased script name. `Comparable` orders
/// by reference first, then script name, which makes save writes and event
/// enqueue order deterministic.
nonisolated public struct PapyrusInstanceKey: Hashable, Comparable, Sendable {
    public let reference: ReferenceKey
    public let scriptName: String

    public init(reference: ReferenceKey, scriptName: String) {
        self.reference = reference
        self.scriptName = PapyrusName.key(scriptName)
    }

    public static func < (left: Self, right: Self) -> Bool {
        if left.reference != right.reference {
            return left.reference < right.reference
        }
        return left.scriptName < right.scriptName
    }
}

/// One persisted script variable. Keys are the lowercased storage keys the
/// instance uses, so a restore addresses the same slots a snapshot read.
nonisolated public struct PapyrusVariableState: Equatable, Sendable {
    public let declaringScript: String
    public let name: String
    public let value: PapyrusValue

    public init(declaringScript: String, name: String, value: PapyrusValue) {
        self.declaringScript = PapyrusName.key(declaringScript)
        self.name = PapyrusName.key(name)
        self.value = value
    }
}

/// Saved state of one script instance, written as a `PSCR` chunk. Object and
/// array values have no world meaning, so they save as `.none`.
nonisolated public struct PapyrusInstanceState: Equatable, Sendable {
    public let key: PapyrusInstanceKey
    public let activeState: String
    /// Sorted by `(declaringScript, name)` for byte-deterministic output.
    public let variables: [PapyrusVariableState]
    public let hasFiredOnInit: Bool

    public init(
        key: PapyrusInstanceKey,
        activeState: String,
        variables: [PapyrusVariableState],
        hasFiredOnInit: Bool
    ) {
        self.key = key
        self.activeState = activeState
        self.variables = variables
        self.hasFiredOnInit = hasFiredOnInit
    }
}

/// One queued script event, delivered FIFO by `PapyrusWorldRuntime`.
nonisolated public struct PapyrusScriptEvent: Equatable, Sendable {
    public let target: PapyrusInstanceKey
    public let functionName: String
    public let arguments: [PapyrusValue]
    /// Script-driven activation depth: 1 for a player use, +1 per nested
    /// `Activate`, capped by `PapyrusWorldRuntime.maximumActivationDepth`.
    public let activationDepth: Int

    public init(
        target: PapyrusInstanceKey,
        functionName: String,
        arguments: [PapyrusValue],
        activationDepth: Int = 0
    ) {
        self.target = target
        self.functionName = functionName
        self.arguments = arguments
        self.activationDepth = activationDepth
    }
}

/// Per-tick ceiling for one 1/30 s step. 32 events drain a ten-script cell attach in
/// one step. The instructions are shared by every script, like the game's
/// `fUpdateBudgetMS`; docs/engine/papyrus-vm.md explains the default.
nonisolated public struct PapyrusTickBudget: Equatable, Sendable {
    public var events: Int
    public var instructions: Int

    public static let standard = PapyrusTickBudget(events: 32, instructions: 4000)

    public init(events: Int, instructions: Int) {
        self.events = events
        self.instructions = instructions
    }
}

/// What one tick of the world runtime did, so callers and tests can assert
/// on carry-over and latent resumes.
nonisolated public struct PapyrusTickReport: Equatable, Sendable {
    /// A tick that did nothing: the report a paused or zero-delta `advance`
    /// returns, and the value `PapyrusWorldRuntime.lastTickReport` starts at.
    public static let zero = PapyrusTickReport(
        steps: 0, dispatched: 0, queued: 0, resumed: 0, faulted: 0
    )

    /// Fixed steps advanced this tick.
    public let steps: Int
    /// Events dispatched (consumed from the queue).
    public let dispatched: Int
    /// Events still queued after the tick, carried to the next one.
    public let queued: Int
    /// Latent calls resumed by the scheduler.
    public let resumed: Int
    /// Faults observed, from event dispatch and latent resumes combined.
    public let faulted: Int

    /// Combines consecutive step reports: counters add, `queued` is the
    /// latest queue depth.
    public func adding(_ next: PapyrusTickReport) -> PapyrusTickReport {
        PapyrusTickReport(
            steps: steps + next.steps,
            dispatched: dispatched + next.dispatched,
            queued: next.queued,
            resumed: resumed + next.resumed,
            faulted: faulted + next.faulted
        )
    }

    public init(steps: Int, dispatched: Int, queued: Int, resumed: Int, faulted: Int) {
        self.steps = steps
        self.dispatched = dispatched
        self.queued = queued
        self.resumed = resumed
        self.faulted = faulted
    }
}

/// Why the world runtime skipped an attach, an event, or a piece of save
/// data. Skips are counted, never faults: malformed or unknown input must
/// not crash.
nonisolated public enum PapyrusWorldSkipReason: SkipTallyKind {
    case removedScript
    case missingScript
    case instanceCreationFailed
    case bindingFailed
    case retiredEventTarget
    case undefinedEventFunction
    case unknownSaveScript
    case unknownSaveVariable
    case unknownSaveTimerTarget
    /// A stage fragment named a script the quest has no live instance of.
    case missingQuestFragmentInstance

    public var name: String {
        switch self {
        case .removedScript: "VMAD script marked removed"
        case .missingScript: "script missing from library"
        case .instanceCreationFailed: "instance creation failed"
        case .bindingFailed: "VMAD property binding failed"
        case .retiredEventTarget: "event target already retired"
        case .undefinedEventFunction: "event function not defined"
        case .unknownSaveScript: "saved script unknown"
        case .unknownSaveVariable: "saved variable unknown"
        case .unknownSaveTimerTarget: "saved timer target unknown"
        case .missingQuestFragmentInstance: "quest fragment instance missing"
        }
    }
}

/// Counter set for `PapyrusWorldSkipReason`, mirroring `ScriptBindingTally`
/// so inspection UI can rank both the same way.
public typealias PapyrusWorldSkipTally = SkipTally<PapyrusWorldSkipReason>
