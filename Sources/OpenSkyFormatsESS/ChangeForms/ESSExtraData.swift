// Extra data lists inside reference change forms and inventory entries. A type with no
// documented layout stops the list: nothing after it can be found. Layouts and the
// types left out: docs/formats/ess-change-forms.md#extra-data.

import Foundation

nonisolated public enum ESSExtraData: Equatable, Sendable {
    case worn
    case wornLeft
    case ownership(ESSRefID)
    case count(UInt16)
    case health(Float)
    case charge(Float)
    case lock(level: UInt8, key: ESSRefID)
    case enchantment(ESSRefID)
    case aliasInstances([ESSAliasInstance])
    case other(type: UInt8)

    public var type: UInt8 {
        switch self {
        case .worn: 22
        case .wornLeft: 23
        case .ownership: 33
        case .count: 36
        case .health: 37
        case .charge: 40
        case .lock: 42
        case .enchantment: 155
        case .aliasInstances: 136
        case let .other(type): type
        }
    }
}

nonisolated public struct ESSAliasInstance: Equatable, Sendable {
    public let quest: ESSRefID
    public let aliasID: UInt32
}

nonisolated public struct ESSExtraDataList: Equatable, Sendable {
    public let entries: [ESSExtraData]
    /// The first entry type with no known layout. Every byte after it is unread.
    public let blockedBy: UInt8?

    public static let empty = ESSExtraDataList(entries: [], blockedBy: nil)

    public var isComplete: Bool {
        blockedBy == nil
    }

    public func contains(_ type: UInt8) -> Bool {
        entries.contains { $0.type == type }
    }

    static func read(_ reader: inout ESSReader) throws(ESSError) -> Self {
        let count = try reader.count("extra data", minimumElementSize: 1)
        var entries: [ESSExtraData] = []
        for _ in 0 ..< count {
            let type = try reader.uint8("extra data type")
            guard let entry = try ESSExtraDataLayout.read(type: type, from: &reader) else {
                return Self(entries: entries, blockedBy: type)
            }
            entries.append(entry)
        }
        return Self(entries: entries, blockedBy: nil)
    }
}

/// How to read or skip each extra data type UESP documents completely.
nonisolated enum ESSExtraDataLayout {
    /// Fixed byte sizes. Both UESP tables agree on each one.
    static let fixedSizes: [UInt8: Int] = [
        24: 19, 25: 13, 28: 3, 29: 0, 30: 4, 31: 1, 34: 3, 35: 3, 39: 4, 43: 28, 44: 1,
        46: 5, 47: 4, 56: 3, 61: 0, 62: 7, 69: 3, 72: 3, 77: 1, 79: 2, 83: 4, 84: 1, 85: 4,
        88: 7, 89: 4, 93: 4, 101: 3, 104: 3, 106: 7, 112: 3, 133: 3, 142: 3, 146: 3,
        149: 7, 150: 1, 156: 1, 157: 3, 159: 6, 160: 4, 161: 88, 164: 3, 169: 11, 176: 8
    ]

    /// A `vsval` count of elements of one fixed size.
    static let repeatedSizes: [UInt8: Int] = [
        27: 4, 52: 8, 68: 4, 111: 11, 120: 8, 140: 3
    ]

    static func read(type: UInt8, from reader: inout ESSReader) throws(ESSError) -> ESSExtraData? {
        if let typed = try readTyped(type: type, from: &reader) {
            return typed
        }
        if let size = fixedSizes[type] {
            try reader.skip(size, "extra data \(type)")
            return .other(type: type)
        }
        if let size = repeatedSizes[type] {
            let count = try reader.count("extra data \(type)", minimumElementSize: size)
            try reader.skip(count * size, "extra data \(type)")
            return .other(type: type)
        }
        return try readVariable(type: type, from: &reader)
    }

    private static func readTyped(
        type: UInt8, from reader: inout ESSReader
    ) throws(ESSError) -> ESSExtraData? {
        switch type {
        case 22: return .worn
        case 23: return .wornLeft
        case 33: return try .ownership(reader.refID("ownership"))
        case 36: return try .count(reader.uint16("extra count"))
        case 37: return try .health(reader.float32("extra health"))
        case 40: return try .charge(reader.float32("extra charge"))
        case 42:
            let level = try reader.uint8("lock level")
            _ = try reader.uint8("lock flags")
            let key = try reader.refID("lock key")
            try reader.skip(8, "lock")
            return .lock(level: level, key: key)
        case 155:
            let enchantment = try reader.refID("enchantment")
            _ = try reader.uint16("enchantment charge")
            return .enchantment(enchantment)
        case 136:
            let count = try reader.count("alias instances", minimumElementSize: 7)
            var aliases: [ESSAliasInstance] = []
            for _ in 0 ..< count {
                try aliases.append(ESSAliasInstance(
                    quest: reader.refID("alias quest"), aliasID: reader.uint32("alias id")
                ))
            }
            return .aliasInstances(aliases)
        default: return nil
        }
    }

    /// Layouts with nested counts or optional parts. Nil means unknown: the list stops.
    private static func readVariable(
        type: UInt8, from reader: inout ESSReader
    ) throws(ESSError) -> ESSExtraData? {
        switch type {
        case 26:
            // TresPassPackage: only a null package has a documented size.
            guard try reader.refID("trespass package").isNull else { return nil }
        case 50:
            _ = try reader.refID("magic target")
            let count = try reader.count("magic targets", minimumElementSize: 6)
            for _ in 0 ..< count {
                try reader.skip(4, "magic target")
                _ = try reader.vsval("magic target")
                try reader.skip(reader.count("magic target data"), "magic target data")
            }
        case 76:
            _ = try reader.wstring("info general topic")
            try reader.skip(5 + 4 * 3, "info general topic")
        case 91:
            let count = try reader.count("faction changes", minimumElementSize: 4)
            try reader.skip(count * 4 + 4, "faction changes")
        case 108:
            // PackageData: only an empty one, 0xFF, has a documented size.
            guard try reader.uint8("package data") == 0xFF else { return nil }
        case 153:
            let first = try reader.refID("text display")
            let second = try reader.refID("text display")
            if try reader.int32("text display") == -2, first.isNull, second.isNull {
                _ = try reader.wstring("text display")
            }
        case 175:
            let count = try reader.count32("scripted animation", minimumElementSize: 7)
            try reader.skip(count * 7, "scripted animation")
        default:
            return nil
        }
        return .other(type: type)
    }
}
