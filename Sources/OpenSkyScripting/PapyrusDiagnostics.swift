// Bounded execution policy, typed faults, outcomes, and coverage tally.

import Foundation
import OpenSkyFormatsPEX
import OpenSkyScriptingInterface

nonisolated public struct PapyrusLimits: Equatable, Sendable {
    /// Instructions one call runs before it yields to the next tick.
    public var instructionBudget = 100_000
    public var callDepth = 256
    public var inheritanceDepth = 64
    public var arrayLength = 100_000
    public var tallyNames = 256
    public var faultRecords = 64
    public var nativeCallRecords = 1024

    public static let standard = PapyrusLimits()
}

nonisolated public enum PapyrusFault: Error, Equatable, Sendable {
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

    public var kind: String {
        switch self {
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

nonisolated public enum PapyrusRunOutcome {
    case completed(PapyrusValue)
    case faulted(PapyrusFault)
    case suspended(SuspendedCall)
}

nonisolated public struct PapyrusTallySnapshot: Equatable, Sendable {
    public let nativeCallTotal: Int
    public let unimplementedNativeTotal: Int
    public let suspensionTotal: Int
    public let faultTotal: Int
}

nonisolated public final class PapyrusTally {
    public let limits: PapyrusLimits

    public private(set) var runs = 0
    public private(set) var instructionsExecuted = 0
    /// Indexed by opcode byte, because the run loop counts every instruction.
    private var countsByOpcodeByte = [Int](repeating: 0, count: 256)
    public private(set) var nativeCallCounts: [String: Int] = [:]
    public private(set) var nativeCallTotal = 0
    public private(set) var unnamedNativeCalls = 0
    public private(set) var unimplementedNativeCounts: [String: Int] = [:]
    public private(set) var unimplementedNativeTotal = 0
    public private(set) var unnamedUnimplementedNatives = 0
    public private(set) var nativeFailureCounts: [String: Int] = [:]
    public private(set) var nativeFailureTotal = 0
    public private(set) var deferredAnimationTotal = 0
    public private(set) var stubbedNativeTotal = 0
    /// Activations refused because the chain reached
    /// `PapyrusWorldRuntime.maximumActivationDepth`.
    public private(set) var activationRecursionCappedTotal = 0
    /// Variables skipped because an earlier one in the same object has the
    /// same case-folded name; the first declaration wins.
    public private(set) var duplicateVariableTotal = 0
    public private(set) var suspensionTotal = 0
    /// Method calls on `None`, which return the declared default instead of faulting.
    public private(set) var noneReceiverTotal = 0
    public private(set) var faultTotal = 0
    public private(set) var faultKindCounts: [String: Int] = [:]
    public private(set) var faults: [PapyrusFault] = []
    /// Kept past the `faults` cap, so an event can name the newest fault.
    public private(set) var lastFault: String?

    public init(limits: PapyrusLimits = .standard) {
        self.limits = limits
    }

    public var rankedUnimplementedNatives: [(name: String, count: Int)] {
        Self.ranked(unimplementedNativeCounts)
    }

    public var rankedNativeFailures: [(name: String, count: Int)] {
        Self.ranked(nativeFailureCounts)
    }

    public var rankedFaultKinds: [(name: String, count: Int)] {
        Self.ranked(faultKindCounts)
    }

    public var snapshot: PapyrusTallySnapshot {
        PapyrusTallySnapshot(
            nativeCallTotal: nativeCallTotal,
            unimplementedNativeTotal: unimplementedNativeTotal,
            suspensionTotal: suspensionTotal,
            faultTotal: faultTotal
        )
    }

    public func noteRun() {
        runs += 1
    }

    public func noteInstruction(_ opcode: PexOpcode) {
        instructionsExecuted += 1
        countsByOpcodeByte[Int(opcode.rawValue)] += 1
    }

    public var opcodeCounts: [PexOpcode: Int] {
        var counts: [PexOpcode: Int] = [:]
        for (byte, count) in countsByOpcodeByte.enumerated() where count > 0 {
            counts[PexOpcode(rawValue: UInt8(byte))] = count
        }
        return counts
    }

    public func noteNative(_ call: PapyrusNativeCall) {
        nativeCallTotal += 1
        let name = call.qualifiedName
        if nativeCallCounts[name] != nil || nativeCallCounts.count < limits.tallyNames {
            nativeCallCounts[name, default: 0] += 1
        } else {
            unnamedNativeCalls += 1
        }
    }

    public func noteNativeFailure(
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

    public func noteDeviation(_ deviation: PapyrusNativeDeviation) {
        switch deviation {
        case .deferredAnimation:
            deferredAnimationTotal += 1
        case .stubbed:
            stubbedNativeTotal += 1
        }
    }

    /// One `Activate` refused because the activation chain hit its depth cap.
    public func noteActivationRecursionCapped() {
        activationRecursionCappedTotal += 1
    }

    public func noteDuplicateVariable() {
        duplicateVariableTotal += 1
    }

    public func noteSuspension() {
        suspensionTotal += 1
    }

    public func noteNoneReceiver() {
        noneReceiverTotal += 1
    }

    public func noteFault(_ fault: PapyrusFault, in script: String? = nil) {
        faultTotal += 1
        lastFault = script.map { "\($0): \(fault)" } ?? "\(fault)"
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
