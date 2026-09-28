// Shared dialogue-record decode bookkeeping. DIAL, INFO and VTYP are kept as
// separate models, but they follow one defensive rule: a malformed or unknown
// subrecord is counted and dropped without making the rest of the record
// unusable.
//
// References:
//   UESP Skyrim Mod:Mod File Format/DIAL, /INFO and /VTYP.
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, DIAL line 4754,
//   INFO line 7796 and VTYP line 6295.

import Foundation
import OpenSkyFormatsCore

nonisolated public enum DialogueSkipKind: Hashable, Sendable {
    case unknownField(FourCC)
    case malformedField(FourCC)
    case orphanResponseField(FourCC)

    public var name: String {
        switch self {
        case let .unknownField(type): "unknown \(type)"
        case let .malformedField(type): "malformed \(type)"
        case let .orphanResponseField(type): "orphan response \(type)"
        }
    }
}

nonisolated public struct DialogueTally: Equatable, Sendable {
    public private(set) var counts: [DialogueSkipKind: Int] = [:]

    public var total: Int {
        counts.values.reduce(0, +)
    }

    public var isEmpty: Bool {
        counts.isEmpty
    }

    public var ranked: [(name: String, count: Int)] {
        counts
            .sorted {
                if $0.value != $1.value {
                    return $0.value > $1.value
                }
                return $0.key.name < $1.key.name
            }
            .map { (name: $0.key.name, count: $0.value) }
    }

    public mutating func note(_ kind: DialogueSkipKind) {
        counts[kind, default: 0] += 1
    }
}
