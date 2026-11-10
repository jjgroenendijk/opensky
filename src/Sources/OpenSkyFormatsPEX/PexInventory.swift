// Bounded-name, uncapped-total census for the Papyrus surface a vanilla
// install actually uses. This evidence sizes the interpreter and native
// registry instead of relying on remembered Papyrus behavior.

import Foundation

nonisolated struct PexCallTarget: Equatable, Hashable, Sendable {
    let object: String
    let function: String

    var name: String {
        "\(object).\(function)"
    }
}

nonisolated struct PexInventory: Equatable, Sendable {
    static let defaultNameLimit = 1024

    let nameLimit: Int

    private(set) var scriptTotal = 0
    private(set) var functionTotal = 0
    private(set) var instructionTotal = 0
    private(set) var opcodeCounts: [PexOpcode: Int] = [:]
    private(set) var externalCallCounts: [PexCallTarget: Int] = [:]
    private(set) var externalCallTotal = 0
    private(set) var unnamedExternalCalls = 0
    private(set) var decodeFailureNames: [String: Int] = [:]
    private(set) var decodeFailureTotal = 0
    private(set) var unnamedDecodeFailures = 0

    init(nameLimit: Int = PexInventory.defaultNameLimit) {
        self.nameLimit = max(0, nameLimit)
    }

    mutating func record(_ file: PexFile) {
        scriptTotal += 1
        for object in file.objects {
            for function in object.functions {
                functionTotal += 1
                for instruction in function.instructions {
                    instructionTotal += 1
                    opcodeCounts[instruction.opcode, default: 0] += 1
                    if
                        let target = Self.callTarget(
                            instruction,
                            parentClassName: object.parentClassName
                        )
                    {
                        noteExternalCall(target)
                    }
                }
            }
        }
    }

    mutating func noteDecodeFailure(path: String) {
        decodeFailureTotal += 1
        if decodeFailureNames[path] != nil || decodeFailureNames.count < nameLimit {
            decodeFailureNames[path, default: 0] += 1
        } else {
            unnamedDecodeFailures += 1
        }
    }

    var unknownOpcodeTotal: Int {
        opcodeCounts.reduce(0) { partial, entry in
            if case .unknown = entry.key {
                partial + entry.value
            } else {
                partial
            }
        }
    }

    var rankedOpcodes: [(name: String, count: Int)] {
        opcodeCounts
            .sorted {
                $0.value == $1.value
                    ? $0.key.rawValue < $1.key.rawValue
                    : $0.value > $1.value
            }
            .map { ($0.key.name, $0.value) }
    }

    var rankedExternalCalls: [(name: String, count: Int)] {
        externalCallCounts
            .sorted {
                $0.value == $1.value
                    ? $0.key.name < $1.key.name
                    : $0.value > $1.value
            }
            .map { ($0.key.name, $0.value) }
    }

    var rankedDecodeFailures: [(name: String, count: Int)] {
        decodeFailureNames
            .sorted {
                $0.value == $1.value
                    ? $0.key < $1.key
                    : $0.value > $1.value
            }
            .map { ($0.key, $0.value) }
    }

    private mutating func noteExternalCall(_ target: PexCallTarget) {
        externalCallTotal += 1
        if externalCallCounts[target] != nil || externalCallCounts.count < nameLimit {
            externalCallCounts[target, default: 0] += 1
        } else {
            unnamedExternalCalls += 1
        }
    }

    private static func callTarget(
        _ instruction: PexInstruction,
        parentClassName: String
    ) -> PexCallTarget? {
        let operands = instruction.operands
        switch instruction.opcode {
        case .callMethod:
            guard
                operands.count >= 2,
                let function = operands[0].stringValue,
                let object = operands[1].stringValue
            else { return nil }
            return PexCallTarget(object: object, function: function)
        case .callParent:
            guard let function = operands.first?.stringValue else { return nil }
            return PexCallTarget(object: parentClassName, function: function)
        case .callStatic:
            guard
                operands.count >= 2,
                let object = operands[0].stringValue,
                let function = operands[1].stringValue
            else { return nil }
            return PexCallTarget(object: object, function: function)
        default:
            return nil
        }
    }
}
