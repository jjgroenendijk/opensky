// Clean in-memory models for the object, property, variable and state sections
// of a Skyrim PEX file. String-table indices never escape the decoder.

import Foundation

nonisolated public struct PexVariable: Equatable, Sendable {
    public let name: String
    public let typeName: String
    public let userFlags: UInt32
    public let initialValue: PexValue
}

nonisolated public struct PexTypedName: Equatable, Sendable {
    public let name: String
    public let typeName: String
}

nonisolated public struct PexPropertyFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let readable = PexPropertyFlags(rawValue: 1 << 0)
    public static let writable = PexPropertyFlags(rawValue: 1 << 1)
    public static let automatic = PexPropertyFlags(rawValue: 1 << 2)
}

nonisolated public struct PexProperty: Equatable, Sendable {
    public let name: String
    public let typeName: String
    public let documentation: String
    public let userFlags: UInt32
    public let flags: PexPropertyFlags
    public let automaticVariableName: String?
    public let readHandler: PexFunction?
    public let writeHandler: PexFunction?
}

nonisolated public struct PexState: Equatable, Sendable {
    public let name: String
    public let functions: [PexNamedFunction]
}

nonisolated public struct PexObject: Equatable, Sendable {
    public let name: String
    public let parentClassName: String
    public let documentation: String
    public let userFlags: UInt32
    public let automaticStateName: String
    public let variables: [PexVariable]
    public let properties: [PexProperty]
    public let states: [PexState]

    public var functions: [PexFunction] {
        properties.flatMap { [$0.readHandler, $0.writeHandler].compactMap(\.self) }
            + states.flatMap { $0.functions.map(\.function) }
    }
}
