// Value types for the main-actor Papyrus world runtime (issue #171):
// instance identity, persisted instance state, queued script events, and the
// per-tick budget and report.

import Foundation

/// World-side identity of one attached script instance: the reference the
/// script is attached to plus its lowercased script name. `Comparable` orders
/// by reference first, then script name, which makes save writes and event
/// enqueue order deterministic.
nonisolated struct PapyrusInstanceKey: Hashable, Comparable, Sendable {
    let reference: ReferenceKey
    let scriptName: String

    init(reference: ReferenceKey, scriptName: String) {
        self.reference = reference
        self.scriptName = PapyrusRuntime.key(scriptName)
    }

    static func < (left: Self, right: Self) -> Bool {
        if left.reference != right.reference {
            return left.reference < right.reference
        }
        return left.scriptName < right.scriptName
    }
}

/// One persisted script variable. Keys are the lowercased storage keys the
/// instance uses, so a restore addresses the same slots a snapshot read.
nonisolated struct PapyrusVariableState: Equatable, Sendable {
    let declaringScript: String
    let name: String
    let value: PapyrusValue

    init(declaringScript: String, name: String, value: PapyrusValue) {
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
nonisolated struct PapyrusInstanceState: Equatable, Sendable {
    let key: PapyrusInstanceKey
    let activeState: String
    /// Sorted by `(declaringScript, name)` for byte-deterministic output.
    let variables: [PapyrusVariableState]
    let hasFiredOnInit: Bool
}

/// One queued script event, delivered FIFO by `PapyrusWorldRuntime`.
nonisolated struct PapyrusScriptEvent: Equatable, Sendable {
    let target: PapyrusInstanceKey
    let functionName: String
    let arguments: [PapyrusValue]
}

/// Per-tick dispatch ceiling.
///
/// The defaults bound one 1/30 s step, not throughput: 32 events keeps a
/// burst (a cell attach enqueues three events per instance, so a ten-script
/// cell drains in one step) while a mass attach carries over instead of
/// hitching the frame, and 100 000 instructions is a tenth of the existing
/// per-invocation `PapyrusLimits.instructionBudget`, so one runaway handler
/// cannot consume more of a frame than a whole invocation may consume total.
nonisolated struct PapyrusTickBudget: Equatable, Sendable {
    var events: Int
    var instructions: Int

    static let standard = PapyrusTickBudget(events: 32, instructions: 100_000)
}

/// What one tick of the world runtime did, so callers and tests can assert
/// on carry-over and latent resumes.
nonisolated struct PapyrusTickReport: Equatable, Sendable {
    /// Fixed steps advanced this tick.
    let steps: Int
    /// Events dispatched (consumed from the queue).
    let dispatched: Int
    /// Events still queued after the tick, carried to the next one.
    let queued: Int
    /// Latent calls resumed by the scheduler.
    let resumed: Int
    /// Faults observed, from event dispatch and latent resumes combined.
    let faulted: Int

    /// Combines consecutive step reports: counters add, `queued` is the
    /// latest queue depth.
    func adding(_ next: PapyrusTickReport) -> PapyrusTickReport {
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
nonisolated enum PapyrusWorldSkipReason: Hashable, Sendable {
    case removedScript
    case missingScript
    case instanceCreationFailed
    case bindingFailed
    case retiredEventTarget
    case undefinedEventFunction
    case unknownSaveScript
    case unknownSaveVariable

    var name: String {
        switch self {
        case .removedScript: "VMAD script marked removed"
        case .missingScript: "script missing from library"
        case .instanceCreationFailed: "instance creation failed"
        case .bindingFailed: "VMAD property binding failed"
        case .retiredEventTarget: "event target already retired"
        case .undefinedEventFunction: "event function not defined"
        case .unknownSaveScript: "saved script unknown"
        case .unknownSaveVariable: "saved variable unknown"
        }
    }
}

/// Counter set for `PapyrusWorldSkipReason`, mirroring `ScriptBindingTally`
/// so inspection UI can rank both the same way.
nonisolated struct PapyrusWorldSkipTally: Equatable, Sendable {
    private(set) var counts: [PapyrusWorldSkipReason: Int] = [:]

    var total: Int {
        counts.values.reduce(0, +)
    }

    var ranked: [(name: String, count: Int)] {
        counts
            .sorted {
                $0.value == $1.value
                    ? $0.key.name < $1.key.name
                    : $0.value > $1.value
            }
            .map { ($0.key.name, $0.value) }
    }

    mutating func note(_ reason: PapyrusWorldSkipReason) {
        counts[reason, default: 0] += 1
    }
}
