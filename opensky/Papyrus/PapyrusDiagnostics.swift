// Bounded execution policy, typed faults, outcomes, and coverage tally.

import Foundation

nonisolated struct PapyrusLimits: Equatable, Sendable {
    var instructionBudget = 1_000_000
    var callDepth = 256
    var inheritanceDepth = 64
    var arrayLength = 100_000
    var tallyNames = 256
    var faultRecords = 64
    var nativeCallRecords = 1024

    static let standard = PapyrusLimits()
}

nonisolated enum PapyrusFault: Error, Equatable, Sendable {
    case budgetExhausted(instruction: Int)
    case callDepthExceeded(instruction: Int)
    case invalidJump(instruction: Int, target: Int)
    case typeMismatch(instruction: Int, expected: String, actual: String)
    case unknownOpcode(instruction: Int, rawValue: UInt8)
    case invalidOperand(instruction: Int, detail: String)
    case divideByZero(instruction: Int)
    case arrayBounds(instruction: Int, index: Int, count: Int)
    case arrayLimitExceeded(instruction: Int, requested: Int)
    case missingFunction(instruction: Int, script: String, function: String)
    case missingProperty(instruction: Int, script: String, property: String)
    case missingInstance(PapyrusObjectHandle)
    case inheritanceDepthExceeded(script: String)
    case invalidResume

    var kind: String {
        switch self {
        case .budgetExhausted: "budgetExhausted"
        case .callDepthExceeded: "callDepthExceeded"
        case .invalidJump: "invalidJump"
        case .typeMismatch: "typeMismatch"
        case .unknownOpcode: "unknownOpcode"
        case .invalidOperand: "invalidOperand"
        case .divideByZero: "divideByZero"
        case .arrayBounds: "arrayBounds"
        case .arrayLimitExceeded: "arrayLimitExceeded"
        case .missingFunction: "missingFunction"
        case .missingProperty: "missingProperty"
        case .missingInstance: "missingInstance"
        case .inheritanceDepthExceeded: "inheritanceDepthExceeded"
        case .invalidResume: "invalidResume"
        }
    }
}

nonisolated enum PapyrusRunOutcome {
    case completed(PapyrusValue)
    case faulted(PapyrusFault)
    case suspended(SuspendedCall)
}

nonisolated struct PapyrusTallySnapshot: Equatable, Sendable {
    let runs: Int
    let instructionsExecuted: Int
    let nativeCallCounts: [String: Int]
    let nativeCallTotal: Int
    let unnamedNativeCalls: Int
    let unimplementedNativeCounts: [String: Int]
    let unimplementedNativeTotal: Int
    let unnamedUnimplementedNatives: Int
    let nativeFailureCounts: [String: Int]
    let nativeFailureTotal: Int
    let deferredAnimationTotal: Int
    let suspensionTotal: Int
    let faultTotal: Int
    let faultKindCounts: [String: Int]
    let faults: [PapyrusFault]
}

nonisolated final class PapyrusTally {
    let limits: PapyrusLimits

    private(set) var runs = 0
    private(set) var instructionsExecuted = 0
    private(set) var opcodeCounts: [PexOpcode: Int] = [:]
    private(set) var nativeCallCounts: [String: Int] = [:]
    private(set) var nativeCallTotal = 0
    private(set) var unnamedNativeCalls = 0
    private(set) var unimplementedNativeCounts: [String: Int] = [:]
    private(set) var unimplementedNativeTotal = 0
    private(set) var unnamedUnimplementedNatives = 0
    private(set) var nativeFailureCounts: [String: Int] = [:]
    private(set) var nativeFailureTotal = 0
    private(set) var deferredAnimationTotal = 0
    private(set) var suspensionTotal = 0
    private(set) var faultTotal = 0
    private(set) var faultKindCounts: [String: Int] = [:]
    private(set) var faults: [PapyrusFault] = []

    init(limits: PapyrusLimits = .standard) {
        self.limits = limits
    }

    var rankedNativeCalls: [(name: String, count: Int)] {
        Self.ranked(nativeCallCounts)
    }

    var rankedUnimplementedNatives: [(name: String, count: Int)] {
        Self.ranked(unimplementedNativeCounts)
    }

    var rankedNativeFailures: [(name: String, count: Int)] {
        Self.ranked(nativeFailureCounts)
    }

    var rankedFaultKinds: [(name: String, count: Int)] {
        Self.ranked(faultKindCounts)
    }

    var snapshot: PapyrusTallySnapshot {
        PapyrusTallySnapshot(
            runs: runs,
            instructionsExecuted: instructionsExecuted,
            nativeCallCounts: nativeCallCounts,
            nativeCallTotal: nativeCallTotal,
            unnamedNativeCalls: unnamedNativeCalls,
            unimplementedNativeCounts: unimplementedNativeCounts,
            unimplementedNativeTotal: unimplementedNativeTotal,
            unnamedUnimplementedNatives: unnamedUnimplementedNatives,
            nativeFailureCounts: nativeFailureCounts,
            nativeFailureTotal: nativeFailureTotal,
            deferredAnimationTotal: deferredAnimationTotal,
            suspensionTotal: suspensionTotal,
            faultTotal: faultTotal,
            faultKindCounts: faultKindCounts,
            faults: faults
        )
    }

    func noteRun() {
        runs += 1
    }

    func noteInstruction(_ opcode: PexOpcode) {
        instructionsExecuted += 1
        opcodeCounts[opcode, default: 0] += 1
    }

    func noteNative(_ call: PapyrusNativeCall) {
        nativeCallTotal += 1
        let name = call.qualifiedName
        if nativeCallCounts[name] != nil || nativeCallCounts.count < limits.tallyNames {
            nativeCallCounts[name, default: 0] += 1
        } else {
            unnamedNativeCalls += 1
        }
    }

    func noteNativeFailure(
        _ failure: PapyrusNativeFailure,
        call: PapyrusNativeCall
    ) {
        switch failure {
        case .unimplemented:
            unimplementedNativeTotal += 1
            if
                unimplementedNativeCounts[call.qualifiedName] != nil
                || unimplementedNativeCounts.count < limits.tallyNames
            {
                unimplementedNativeCounts[call.qualifiedName, default: 0] += 1
            } else {
                unnamedUnimplementedNatives += 1
            }
        case .invalidArguments:
            nativeFailureTotal += 1
            Self.bump(
                &nativeFailureCounts,
                call.qualifiedName,
                limit: limits.tallyNames
            )
        }
    }

    func noteDeviation(_ deviation: PapyrusNativeDeviation) {
        switch deviation {
        case .deferredAnimation:
            deferredAnimationTotal += 1
        }
    }

    func noteSuspension() {
        suspensionTotal += 1
    }

    func noteFault(_ fault: PapyrusFault) {
        faultTotal += 1
        faultKindCounts[fault.kind, default: 0] += 1
        if faults.count < limits.faultRecords {
            faults.append(fault)
        }
    }

    private static func ranked(
        _ counts: [String: Int]
    ) -> [(name: String, count: Int)] {
        counts
            .sorted {
                $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
            }
            .map { ($0.key, $0.value) }
    }

    private static func bump(
        _ counts: inout [String: Int],
        _ name: String,
        limit: Int
    ) {
        if counts[name] != nil || counts.count < limit {
            counts[name, default: 0] += 1
        }
    }
}
