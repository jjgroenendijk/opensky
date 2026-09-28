// Clean in-memory models for the object, property, variable and state sections
// of a Skyrim PEX file. String-table indices never escape the decoder.

import Foundation

nonisolated package struct PexVariable: Equatable, Sendable {
    package let name: String
    package let typeName: String
    package let userFlags: UInt32
    package let initialValue: PexValue
}

nonisolated package struct PexTypedName: Equatable, Sendable {
    package let name: String
    package let typeName: String
}

nonisolated package struct PexPropertyFlags: OptionSet, Equatable, Sendable {
    package let rawValue: UInt8

    package init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    package static let readable = PexPropertyFlags(rawValue: 1 << 0)
    package static let writable = PexPropertyFlags(rawValue: 1 << 1)
    package static let automatic = PexPropertyFlags(rawValue: 1 << 2)
}

nonisolated package struct PexProperty: Equatable, Sendable {
    package let name: String
    package let typeName: String
    package let documentation: String
    package let userFlags: UInt32
    package let flags: PexPropertyFlags
    package let automaticVariableName: String?
    package let readHandler: PexFunction?
    package let writeHandler: PexFunction?
}

nonisolated package struct PexState: Equatable, Sendable {
    package let name: String
    package let functions: [PexNamedFunction]
}

nonisolated package struct PexObject: Equatable, Sendable {
    package let name: String
    package let parentClassName: String
    package let documentation: String
    package let userFlags: UInt32
    package let automaticStateName: String
    package let variables: [PexVariable]
    package let properties: [PexProperty]
    package let states: [PexState]

    package var functions: [PexFunction] {
        properties.flatMap { [$0.readHandler, $0.writeHandler].compactMap(\.self) }
            + states.flatMap { $0.functions.map(\.function) }
    }
}
