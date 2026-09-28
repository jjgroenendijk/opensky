// Papyrus function model. Names live on state entries; property accessors use
// the same nameless function body shape directly.

import Foundation

nonisolated package struct PexFunctionFlags: OptionSet, Equatable, Sendable {
    package let rawValue: UInt8

    package init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    package static let global = PexFunctionFlags(rawValue: 1 << 0)
    package static let native = PexFunctionFlags(rawValue: 1 << 1)
}

nonisolated package struct PexFunction: Equatable, Sendable {
    package let returnTypeName: String
    package let documentation: String
    package let userFlags: UInt32
    package let flags: PexFunctionFlags
    package let parameters: [PexTypedName]
    package let localVariables: [PexTypedName]
    package let instructions: [PexInstruction]
}

nonisolated package struct PexNamedFunction: Equatable, Sendable {
    package let name: String
    package let function: PexFunction
}
