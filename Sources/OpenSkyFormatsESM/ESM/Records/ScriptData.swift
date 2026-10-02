// Shared VMAD models for Papyrus scripts on ESM records. QUST and INFO decode
// their fragment tails (ScriptDataQuestFragments.swift,
// ScriptDataInfoFragments.swift); PACK, PERK and SCEN skip theirs. Layout from
// xEdit `wbVMAD` and UESP "VMAD Field".

import Foundation
import OpenSkyFormatsCore

nonisolated public enum ScriptDataError: Error, Equatable, Sendable {
    case binary(BinaryReaderError)
    case unsupportedVersion(Int16)
    case unsupportedObjectFormat(Int16)
    case impossibleCount(context: String, count: UInt32, remaining: Int)
    case arrayRequiresVersionFive(type: UInt8, version: Int16)
    case unknownPropertyType(UInt8)
    case unexpectedTrailingBytes(recordType: FourCC?, count: Int)
    /// A fragment tail whose count is a flag population declared a bit outside
    /// the documented set, so no phase can be paired with an entry. The tail is
    /// refused; the primary scripts survive.
    case unknownFragmentFlags(recordType: FourCC?, flags: UInt8)
}

nonisolated public enum ScriptObjectFormat: Int16, Equatable, Sendable {
    case formIDFirst = 1
    case formIDLast = 2
}

nonisolated public struct ScriptObjectReference: Equatable, Sendable {
    public let formID: FormID
    /// -1 means a direct FormID. Any other value selects an alias on the quest
    /// identified by `formID`. Resolving it needs the running quest's alias
    /// table, so `ScriptDataBinding` takes a seam for it.
    public let alias: Int16
    public let unused: UInt16

    public var isAlias: Bool {
        alias != -1
    }

    public func directReferenceKey(using resolver: FormIDResolver) -> ReferenceKey? {
        guard !isAlias else { return nil }
        return ReferenceKey.resolve(formID, using: resolver)
    }
}

nonisolated public enum ScriptPropertyValue: Equatable, Sendable {
    case none
    case object(ScriptObjectReference)
    case string(String)
    case integer(Int32)
    case float(Float)
    case boolean(Bool)
    case objects([ScriptObjectReference])
    case strings([String])
    case integers([Int32])
    case floats([Float])
    case booleans([Bool])
}

nonisolated public struct ScriptProperty: Equatable, Sendable {
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let edited = Flags(rawValue: 0x01)
        public static let removed = Flags(rawValue: 0x02)
    }

    public let name: String
    public let type: UInt8
    public let flags: Flags
    public let value: ScriptPropertyValue
}

nonisolated public struct AttachedScript: Equatable, Sendable {
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let inherited = Flags(rawValue: 0x01)
        public static let removed = Flags(rawValue: 0x02)
    }

    public let name: String
    public let flags: Flags
    public let properties: [ScriptProperty]

    public init(name: String, flags: Flags, properties: [ScriptProperty]) {
        self.name = name
        self.flags = flags
        self.properties = properties
    }

    public var isRemoved: Bool {
        flags.contains(.removed)
    }
}

nonisolated public enum ScriptDataSkipKind: SkipTallyKind {
    case aliasObject
    case removedProperty
    case fragments(FourCC)

    public var name: String {
        switch self {
        case .aliasObject:
            "alias object"
        case .removedProperty:
            "removed property"
        case let .fragments(recordType):
            "\(recordType) fragments"
        }
    }
}

public typealias ScriptDataTally = SkipTally<ScriptDataSkipKind>

/// Accumulator for a VMAD field inside one record's field loop.
nonisolated public struct ScriptData: Equatable, Sendable {
    public let ownerType: FourCC?
    public var version: Int16?
    public var objectFormat: ScriptObjectFormat?
    public var scripts: [AttachedScript] = []
    /// Decoded QUST tail. Nil for every other carrier, and also for a QUST
    /// whose tail failed to decode — that case keeps the primary scripts and
    /// records one `.fragments("QUST")` tally entry instead.
    public var questFragments: QuestFragmentSection?
    /// Decoded INFO tail. Nil for every other carrier, and also
    /// for an INFO whose tail failed to decode — that case keeps the primary
    /// scripts and records one `.fragments("INFO")` tally entry instead.
    public var infoFragments: TopicInfoFragmentSection?
    /// Decoded SCEN, PACK, or PERK tail. Nil when absent or malformed.
    public var recordFragments: RecordFragmentSection?
    public var skipped = ScriptDataTally()

    public init(ownerType: FourCC? = nil) {
        self.ownerType = ownerType
    }
}
