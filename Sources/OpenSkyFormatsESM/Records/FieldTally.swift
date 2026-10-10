// What a record decoder did not read. Unread and malformed fields are counted,
// never dropped silently, so a real-data sweep can report them.

import Foundation
import OpenSkyFormatsCore

nonisolated public enum FieldSkipKind: SkipTallyKind {
    case unknownField(FourCC)
    case malformedField(FourCC)
    /// A count, size, or link that disagrees with the data around it.
    case mismatch(String)

    public var name: String {
        switch self {
        case let .unknownField(type): "unknown \(type)"
        case let .malformedField(type): "malformed \(type)"
        case let .mismatch(text): text
        }
    }
}

public typealias FieldTally = SkipTally<FieldSkipKind>
