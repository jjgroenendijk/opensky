// Shared VMAD models for Papyrus scripts attached to ESM records.
//
// Layout authority: xEdit dev-4.1.6 `wbDefinitionsTES5.pas`,
// `wbScriptPropertyObject`, `wbScriptEntry`, and `wbVMAD`; cross-checked
// against UESP "Skyrim Mod:Mod File Format/VMAD Field".
// https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas
// https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/VMAD_Field
//
// Fragment carriers have record-specific tails. INFO, PACK, PERK and SCEN
// still record that a tail is present and skip the bounded remainder; QUST
// decodes its tail into `QuestFragmentSection` (see
// ScriptDataQuestFragments.swift), because the quest runtime needs the
// stage-to-fragment mapping and the alias script sections.

import Foundation

nonisolated enum ScriptDataError: Error, Equatable {
    case binary(BinaryReaderError)
    case unsupportedVersion(Int16)
    case unsupportedObjectFormat(Int16)
    case invalidString(offset: Int, length: Int)
    case impossibleCount(context: String, count: UInt32, remaining: Int)
    case arrayRequiresVersionFive(type: UInt8, version: Int16)
    case unknownPropertyType(UInt8)
    case unexpectedTrailingBytes(recordType: FourCC?, count: Int)
}

nonisolated enum ScriptObjectFormat: Int16, Equatable {
    case formIDFirst = 1
    case formIDLast = 2
}

nonisolated struct ScriptObjectReference: Equatable {
    let formID: FormID
    /// -1 means a direct FormID. Any other value selects an alias on the quest
    /// identified by `formID`. M13.1 decodes the alias definitions those slots
    /// name (`Quest.Alias`) and M13.4 fills them at runtime, but the fill is a
    /// world fact rather than a record one: resolving an alias slot to a
    /// reference needs the running quest's table, which is why nothing here
    /// answers it and `ScriptDataBinding` takes a seam for it.
    let alias: Int16
    let unused: UInt16

    var isAlias: Bool {
        alias != -1
    }

    func directReferenceKey(using resolver: FormIDResolver) -> ReferenceKey? {
        guard !isAlias else { return nil }
        return ReferenceKey.resolve(formID, using: resolver)
    }
}

nonisolated enum ScriptPropertyValue: Equatable {
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

nonisolated struct ScriptProperty: Equatable {
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt8

        static let edited = Flags(rawValue: 0x01)
        static let removed = Flags(rawValue: 0x02)
    }

    let name: String
    let type: UInt8
    let flags: Flags
    let value: ScriptPropertyValue
}

nonisolated struct AttachedScript: Equatable {
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt8

        static let inherited = Flags(rawValue: 0x01)
        static let removed = Flags(rawValue: 0x02)
    }

    let name: String
    let flags: Flags
    let properties: [ScriptProperty]

    var isRemoved: Bool {
        flags.contains(.removed)
    }
}

nonisolated enum ScriptDataSkipKind: Hashable {
    case aliasObject
    case removedProperty
    case fragments(FourCC)

    var name: String {
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

nonisolated struct ScriptDataTally: Equatable {
    private(set) var counts: [ScriptDataSkipKind: Int] = [:]

    var total: Int {
        counts.values.reduce(0, +)
    }

    var ranked: [(name: String, count: Int)] {
        counts
            .sorted {
                $0.value == $1.value
                    ? $0.key.name < $1.key.name
                    : $0.value > $1.value
            }
            .map { ($0.key.name, $0.value) }
    }

    mutating func note(_ kind: ScriptDataSkipKind, count: Int = 1) {
        counts[kind, default: 0] += count
    }

    mutating func merge(_ other: ScriptDataTally) {
        for (kind, count) in other.counts {
            note(kind, count: count)
        }
    }
}

/// Accumulator for a VMAD field inside one record's field loop.
nonisolated struct ScriptData: Equatable {
    let ownerType: FourCC?
    var version: Int16?
    var objectFormat: ScriptObjectFormat?
    var scripts: [AttachedScript] = []
    /// Decoded QUST tail. Nil for every other carrier, and also for a QUST
    /// whose tail failed to decode — that case keeps the primary scripts and
    /// records one `.fragments("QUST")` tally entry instead.
    var questFragments: QuestFragmentSection?
    var skipped = ScriptDataTally()

    init(ownerType: FourCC? = nil) {
        self.ownerType = ownerType
    }

    var isEmpty: Bool {
        scripts.isEmpty && questFragments == nil
    }
}
