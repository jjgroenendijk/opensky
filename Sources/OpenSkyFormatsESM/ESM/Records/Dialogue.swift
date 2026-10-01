// Shared decode bookkeeping for DIAL, INFO and VTYP. A malformed or unknown
// subrecord is counted and dropped; the rest of the record stays usable.
// Sources: UESP "Skyrim Mod:Mod File Format" DIAL, INFO, VTYP; xEdit wbDefinitionsTES5.pas.

import Foundation
import OpenSkyFormatsCore

nonisolated public enum DialogueSkipKind: SkipTallyKind {
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

public typealias DialogueTally = SkipTally<DialogueSkipKind>
