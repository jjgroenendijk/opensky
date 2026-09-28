// Value types for the main-actor Papyrus world runtime (issue #171):
// instance identity, persisted instance state, queued script events, and the
// per-tick budget and report.

import Foundation
import OpenSkyFormats

/// World-side identity of one attached script instance: the reference the
/// script is attached to plus its lowercased script name. `Comparable` orders
/// by reference first, then script name, which makes save writes and event
/// enqueue order deterministic.
nonisolated public struct PapyrusInstanceKey: Hashable, Comparable, Sendable {
    public let reference: ReferenceKey
    public let scriptName: String

    public init(reference: ReferenceKey, scriptName: String) {
        self.reference = reference
        self.scriptName = PapyrusRuntime.key(scriptName)
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
        self.declaringScript = PapyrusInstance.key(declaringScript)
        self.name = PapyrusInstance.key(name)
        self.value = value
    }
}

/// Persisted state of one script instance, the unit a `PSCR` save chunk
/// serializes.
///
/// Stated deviation: `PapyrusValue.object` and `PapyrusValue.array` hold
/// runtime-allocated identity with no world meaning, so they are not
/// persistable; `PapyrusWorldRuntime.instanceStates()` snapshots both as
/// `.none` and a restore leaves the PEX default in their place.
nonisolated public struct PapyrusInstanceState: Equatable, Sendable {
    public let key: PapyrusInstanceKey
    public let activeState: String
    /// Sorted by `(declaringScript, name)` for byte-deterministic output.
    public let variables: [PapyrusVariableState]
    public let hasFiredOnInit: Bool
}

/// One queued script event, delivered FIFO by `PapyrusWorldRuntime`.
nonisolated public struct PapyrusScriptEvent: Equatable, Sendable {
    public let target: PapyrusInstanceKey
    public let functionName: String
    public let arguments: [PapyrusValue]
    /// How many script-driven activations deep this event is (issue #172). A
    /// player use key queues `OnActivate` at depth 1; an `Activate` native
    /// called from that handler queues at depth 2, and
    /// `PapyrusWorldRuntime.maximumActivationDepth` stops the chain. Every
    /// other event stays at 0.
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

/// Per-tick dispatch ceiling.
///
/// The defaults bound one 1/30 s step, not throughput: 32 events keeps a
/// burst (a cell attach enqueues three events per instance, so a ten-script
/// cell drains in one step) while a mass attach carries over instead of
/// hitching the frame, and 100 000 instructions is a tenth of the existing
/// per-invocation `PapyrusLimits.instructionBudget`, so one runaway handler
/// cannot consume more of a frame than a whole invocation may consume total.
nonisolated public struct PapyrusTickBudget: Equatable, Sendable {
    public var events: Int
    public var instructions: Int

    public static let standard = PapyrusTickBudget(events: 32, instructions: 100_000)
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
}

/// Why the world runtime skipped an attach, an event, or a piece of save
/// data. Skips are counted, never faults: malformed or unknown input must
/// not crash.
nonisolated public enum PapyrusWorldSkipReason: Hashable, Sendable {
    case removedScript
    case missingScript
    case instanceCreationFailed
    case bindingFailed
    case retiredEventTarget
    case undefinedEventFunction
    case unknownSaveScript
    case unknownSaveVariable
    case unknownSaveTimerTarget
    /// A stage fragment named a script the quest holds no live instance of,
    /// so there was nothing to send the fragment function to (issue #322).
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
nonisolated public struct PapyrusWorldSkipTally: Equatable, Sendable {
    public private(set) var counts: [PapyrusWorldSkipReason: Int] = [:]

    public var total: Int {
        counts.values.reduce(0, +)
    }

    public var ranked: [(name: String, count: Int)] {
        counts
            .sorted {
                $0.value == $1.value
                    ? $0.key.name < $1.key.name
                    : $0.value > $1.value
            }
            .map { ($0.key.name, $0.value) }
    }

    public mutating func note(_ reason: PapyrusWorldSkipReason) {
        counts[reason, default: 0] += 1
    }
}
