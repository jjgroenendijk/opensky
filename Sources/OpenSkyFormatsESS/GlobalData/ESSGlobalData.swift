// One global data table: a type, a length, and bytes. Five types have decoders; every
// other one stays counted bytes. See docs/formats/ess.md#global-data.

import Foundation

nonisolated public enum ESSGlobalDataType: UInt32, CaseIterable, Sendable {
    case miscStats = 0
    case playerLocation = 1
    case tes = 2
    case globalVariables = 3
    case createdObjects = 4
    case effects = 5
    case weather = 6
    case audio = 7
    case skyCells = 8
    case processLists = 100
    case combat = 101
    case interface = 102
    case actorCauses = 103
    case unknown104 = 104
    case detectionManager = 105
    case locationMetaData = 106
    case questStaticData = 107
    case storyTeller = 108
    case magicFavorites = 109
    case playerControls = 110
    case storyEventManager = 111
    case ingredientShared = 112
    case menuControls = 113
    case menuTopicManager = 114
    case tempEffects = 1000
    case papyrus = 1001
    case animObjects = 1002
    case timer = 1003
    case synchronizedAnimations = 1004
    case main = 1005

    public static func name(of rawType: UInt32) -> String {
        Self(rawValue: rawType).map { "\($0)" } ?? "type \(rawType)"
    }
}

nonisolated public struct ESSGlobalData: Equatable, Sendable {
    public let type: UInt32
    public let data: Data

    public init(type: UInt32, data: Data) {
        self.type = type
        self.data = data
    }

    public var knownType: ESSGlobalDataType? {
        ESSGlobalDataType(rawValue: type)
    }

    static func read(_ reader: inout ESSReader, count: Int) throws(ESSError) -> [Self] {
        guard count * 8 <= reader.bytesRemaining else {
            throw .invalidCount(context: "global data table", count: count)
        }
        var tables: [Self] = []
        for _ in 0 ..< count {
            try tables.append(readOne(&reader))
        }
        return tables
    }

    /// Reads tables up to `end`. The third group's count leaves one table out, so it
    /// is read by position instead.
    static func read(_ reader: inout ESSReader, until end: Int) throws(ESSError) -> [Self] {
        var tables: [Self] = []
        while reader.offset < end {
            try tables.append(readOne(&reader))
        }
        guard reader.offset == end else {
            throw .invalidValue(context: "global data table 3 runs past the form id array")
        }
        return tables
    }

    private static func readOne(_ reader: inout ESSReader) throws(ESSError) -> Self {
        let type = try reader.uint32("global data type")
        let length = try Int(reader.uint32("global data length"))
        let name = ESSGlobalDataType.name(of: type)
        return try Self(type: type, data: reader.bytes(length, "global data \(name)"))
    }
}
