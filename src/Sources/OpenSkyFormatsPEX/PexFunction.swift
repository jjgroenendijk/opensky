// Papyrus function model. Names live on state entries; property accessors use
// the same nameless function body shape directly.

import Foundation

nonisolated public struct PexFunctionFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let global = PexFunctionFlags(rawValue: 1 << 0)
    public static let native = PexFunctionFlags(rawValue: 1 << 1)
}

nonisolated public struct PexFunction: Equatable, Sendable {
    public let returnTypeName: String
    public let documentation: String
    public let userFlags: UInt32
    public let flags: PexFunctionFlags
    public let parameters: [PexTypedName]
    public let localVariables: [PexTypedName]
    public let instructions: [PexInstruction]
}

nonisolated public struct PexNamedFunction: Equatable, Sendable {
    public let name: String
    public let function: PexFunction
}
