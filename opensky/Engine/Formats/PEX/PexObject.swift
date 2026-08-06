// Clean in-memory models for the object, property, variable and state sections
// of a Skyrim PEX file. String-table indices never escape the decoder.

import Foundation

nonisolated struct PexVariable: Equatable, Sendable {
    let name: String
    let typeName: String
    let userFlags: UInt32
    let initialValue: PexValue
}

nonisolated struct PexTypedName: Equatable, Sendable {
    let name: String
    let typeName: String
}

nonisolated struct PexPropertyFlags: OptionSet, Equatable, Sendable {
    let rawValue: UInt8

    static let readable = PexPropertyFlags(rawValue: 1 << 0)
    static let writable = PexPropertyFlags(rawValue: 1 << 1)
    static let automatic = PexPropertyFlags(rawValue: 1 << 2)
}

nonisolated struct PexProperty: Equatable, Sendable {
    let name: String
    let typeName: String
    let documentation: String
    let userFlags: UInt32
    let flags: PexPropertyFlags
    let automaticVariableName: String?
    let readHandler: PexFunction?
    let writeHandler: PexFunction?
}

nonisolated struct PexState: Equatable, Sendable {
    let name: String
    let functions: [PexNamedFunction]
}

nonisolated struct PexObject: Equatable, Sendable {
    let name: String
    let parentClassName: String
    let documentation: String
    let userFlags: UInt32
    let automaticStateName: String
    let variables: [PexVariable]
    let properties: [PexProperty]
    let states: [PexState]

    var functions: [PexFunction] {
        properties.flatMap { [$0.readHandler, $0.writeHandler].compactMap(\.self) }
            + states.flatMap { $0.functions.map(\.function) }
    }
}
