// Shared VMAD models for Papyrus scripts attached to ESM records.
//
// Layout authority: xEdit dev-4.1.6 `wbDefinitionsTES5.pas`,
// `wbScriptPropertyObject`, `wbScriptEntry`, and `wbVMAD`; cross-checked
// against UESP "Skyrim Mod:Mod File Format/VMAD Field".
// https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas
// https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/VMAD_Field
//
// Fragment carriers have record-specific tails. PACK, PERK and SCEN still
// record that a tail is present and skip the bounded remainder. QUST decodes
// its tail into `QuestFragmentSection` (see ScriptDataQuestFragments.swift),
// because the quest runtime needs the stage-to-fragment mapping and the alias
// script sections, and INFO decodes its tail into `TopicInfoFragmentSection`
// (see ScriptDataInfoFragments.swift), because the dialogue runtime needs the
// begin/end result scripts of a chosen response.

import Foundation

nonisolated package enum ScriptDataError: Error, Equatable {
    case binary(BinaryReaderError)
    case unsupportedVersion(Int16)
    case unsupportedObjectFormat(Int16)
    case impossibleCount(context: String, count: UInt32, remaining: Int)
    case arrayRequiresVersionFive(type: UInt8, version: Int16)
    case unknownPropertyType(UInt8)
    case unexpectedTrailingBytes(recordType: FourCC?, count: Int)
    /// A fragment tail whose count is a flag population declared a bit outside
    /// the documented set, so no phase can be paired with an entry (issue
    /// #426). The tail is refused; the primary scripts survive.
    case unknownFragmentFlags(recordType: FourCC?, flags: UInt8)
}

nonisolated package enum ScriptObjectFormat: Int16, Equatable {
    case formIDFirst = 1
    case formIDLast = 2
}

nonisolated package struct ScriptObjectReference: Equatable {
    package let formID: FormID
    /// -1 means a direct FormID. Any other value selects an alias on the quest
    /// identified by `formID`. M13.1 decodes the alias definitions those slots
    /// name (`Quest.Alias`) and M13.4 fills them at runtime, but the fill is a
    /// world fact rather than a record one: resolving an alias slot to a
    /// reference needs the running quest's table, which is why nothing here
    /// answers it and `ScriptDataBinding` takes a seam for it.
    package let alias: Int16
    package let unused: UInt16

    package var isAlias: Bool {
        alias != -1
    }

    package func directReferenceKey(using resolver: FormIDResolver) -> ReferenceKey? {
        guard !isAlias else { return nil }
        return ReferenceKey.resolve(formID, using: resolver)
    }
}

nonisolated package enum ScriptPropertyValue: Equatable {
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

nonisolated package struct ScriptProperty: Equatable {
    package struct Flags: OptionSet, Equatable {
        package let rawValue: UInt8

        package init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        package static let edited = Flags(rawValue: 0x01)
        package static let removed = Flags(rawValue: 0x02)
    }

    package let name: String
    package let type: UInt8
    package let flags: Flags
    package let value: ScriptPropertyValue
}

nonisolated package struct AttachedScript: Equatable {
    package struct Flags: OptionSet, Equatable {
        package let rawValue: UInt8

        package init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        package static let inherited = Flags(rawValue: 0x01)
        package static let removed = Flags(rawValue: 0x02)
    }

    package let name: String
    package let flags: Flags
    package let properties: [ScriptProperty]

    package init(name: String, flags: Flags, properties: [ScriptProperty]) {
        self.name = name
        self.flags = flags
        self.properties = properties
    }

    package var isRemoved: Bool {
        flags.contains(.removed)
    }
}

nonisolated package enum ScriptDataSkipKind: Hashable {
    case aliasObject
    case removedProperty
    case fragments(FourCC)

    package var name: String {
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

nonisolated package struct ScriptDataTally: Equatable {
    package private(set) var counts: [ScriptDataSkipKind: Int] = [:]

    package var total: Int {
        counts.values.reduce(0, +)
    }

    package var ranked: [(name: String, count: Int)] {
        counts
            .sorted {
                $0.value == $1.value
                    ? $0.key.name < $1.key.name
                    : $0.value > $1.value
            }
            .map { ($0.key.name, $0.value) }
    }

    package mutating func note(_ kind: ScriptDataSkipKind, count: Int = 1) {
        counts[kind, default: 0] += count
    }

    package mutating func merge(_ other: ScriptDataTally) {
        for (kind, count) in other.counts {
            note(kind, count: count)
        }
    }
}

/// Accumulator for a VMAD field inside one record's field loop.
nonisolated package struct ScriptData: Equatable {
    package let ownerType: FourCC?
    package var version: Int16?
    package var objectFormat: ScriptObjectFormat?
    package var scripts: [AttachedScript] = []
    /// Decoded QUST tail. Nil for every other carrier, and also for a QUST
    /// whose tail failed to decode — that case keeps the primary scripts and
    /// records one `.fragments("QUST")` tally entry instead.
    package var questFragments: QuestFragmentSection?
    /// Decoded INFO tail (issue #426). Nil for every other carrier, and also
    /// for an INFO whose tail failed to decode — that case keeps the primary
    /// scripts and records one `.fragments("INFO")` tally entry instead.
    package var infoFragments: TopicInfoFragmentSection?
    package var skipped = ScriptDataTally()

    package init(ownerType: FourCC? = nil) {
        self.ownerType = ownerType
    }

    package var isEmpty: Bool {
        scripts.isEmpty && questFragments == nil && infoFragments == nil
    }
}
