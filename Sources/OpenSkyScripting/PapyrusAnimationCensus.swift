// The animation event and graph variable names the archived scripts use. The engine
// sends every graph event to `OnAnimationEvent` of the scripts that registered
// (`PapyrusWorldAnimationEvents.swift`), and `GetAnimationVariable*` reads a graph
// variable and `SetAnimationVariable*` writes one. `openskycli gaps` reads the lists
// (docs/tools/gaps.md).

import Foundation
import OpenSkyFormatsPEX

nonisolated public struct PapyrusAnimationCensus: Equatable, Sendable {
    /// Event names, in lower case, passed as a string literal to
    /// `RegisterForAnimationEvent`.
    public private(set) var registeredEvents: Set<String> = []
    /// Variable names, in lower case, passed as a string literal to
    /// `GetAnimationVariableBool`, `GetAnimationVariableInt`, or `GetAnimationVariableFloat`.
    public private(set) var readVariables: Set<String> = []
    /// Variable names, in lower case, passed as a string literal to `SetAnimationVariable*`.
    public private(set) var writtenVariables: Set<String> = []

    static let register = "RegisterForAnimationEvent"
    static let variableReaders = [
        "GetAnimationVariableBool", "GetAnimationVariableInt", "GetAnimationVariableFloat"
    ]
    static let variableWriters = [
        "SetAnimationVariableBool", "SetAnimationVariableInt", "SetAnimationVariableFloat"
    ]

    public init(files: [PexFile]) {
        for object in files.flatMap(\.objects) {
            for function in object.states.flatMap(\.functions).map(\.function) {
                for instruction in function.instructions {
                    registeredEvents.formUnion(Self.literals(instruction, calling: [Self.register]))
                    readVariables.formUnion(
                        Self.literals(instruction, calling: Self.variableReaders)
                    )
                    writtenVariables.formUnion(
                        Self.literals(instruction, calling: Self.variableWriters)
                    )
                }
            }
        }
    }

    /// The string literals among the arguments of a call to one of `names`.
    /// Operand 0 is the function name, 1 the receiver, 2 the result.
    static func literals(_ instruction: PexInstruction, calling names: [String]) -> [String] {
        guard
            instruction.opcode == .callMethod,
            let name = instruction.operands.first?.stringValue,
            names.contains(where: { PapyrusRuntime.matches(name, $0) })
        else { return [] }
        return instruction.operands.dropFirst(3).compactMap { operand in
            guard case let .string(value) = operand, !value.isEmpty else { return nil }
            return value.lowercased()
        }
    }
}
