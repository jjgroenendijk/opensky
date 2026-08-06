// Papyrus function model. Names live on state entries; property accessors use
// the same nameless function body shape directly.

import Foundation

nonisolated struct PexFunctionFlags: OptionSet, Equatable, Sendable {
    let rawValue: UInt8

    static let global = PexFunctionFlags(rawValue: 1 << 0)
    static let native = PexFunctionFlags(rawValue: 1 << 1)
}

nonisolated struct PexFunction: Equatable, Sendable {
    let returnTypeName: String
    let documentation: String
    let userFlags: UInt32
    let flags: PexFunctionFlags
    let parameters: [PexTypedName]
    let localVariables: [PexTypedName]
    let instructions: [PexInstruction]
}

nonisolated struct PexNamedFunction: Equatable, Sendable {
    let name: String
    let function: PexFunction
}
