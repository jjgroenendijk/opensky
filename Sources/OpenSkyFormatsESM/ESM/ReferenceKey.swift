// Session-stable identity for object references. `FormID` is file-relative and
// `ResolvedFormID` keeps the MAST spelling, so neither is a safe key. Rules:
// docs/formats/formid.md and docs/engine/reference-identity.md.

import Foundation

/// Session-stable identity of an object reference: a plugin reference (plugin
/// plus 24-bit object ID) or a generated one (a sequence number). Every plugin
/// key sorts first, by lowercased plugin name then object ID.
nonisolated public enum ReferenceKey: Hashable, Sendable {
    /// Defining plugin plus low 24 bits of the FormID. The associated `name`
    /// is always lowercased — plugin file names are case-insensitive on the
    /// game's original platform and MAST spelling varies between plugins, so
    /// every construction path normalizes it. Build these through
    /// `init(resolved:)` or `resolve(_:using:)` rather than by hand.
    case plugin(name: String, objectID: UInt32)

    /// Runtime-created reference, sequence-numbered by
    /// `GeneratedReferenceAllocator`.
    case generated(UInt64)

    /// The player. `.generated(0)` is reserved by the allocator, so it never
    /// collides and needs no plugin. It is an identity only: nothing draws it.
    /// See docs/engine/reference-identity.md.
    public static let player = ReferenceKey.generated(0)

    /// Normalizes the resolved plugin name to lowercase.
    public init(resolved: ResolvedFormID) {
        self = .plugin(name: resolved.plugin.lowercased(), objectID: resolved.objectID)
    }

    /// Resolves a file-relative FormID against its owning plugin's master
    /// list. Nil for the null FormID, which means "no reference".
    public static func resolve(_ id: FormID, using resolver: FormIDResolver) -> ReferenceKey? {
        guard let resolved = resolver.resolve(id) else { return nil }
        return ReferenceKey(resolved: resolved)
    }
}

nonisolated extension ReferenceKey: Comparable {
    public static func < (lhs: ReferenceKey, rhs: ReferenceKey) -> Bool {
        switch (lhs, rhs) {
        case let (.plugin(leftName, leftObject), .plugin(rightName, rightObject)):
            leftName == rightName ? leftObject < rightObject : leftName < rightName
        case let (.generated(left), .generated(right)):
            left < right
        case (.plugin, .generated):
            true
        case (.generated, .plugin):
            false
        }
    }
}

nonisolated extension ReferenceKey: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .plugin(name, objectID):
            String(format: "%@:%06X", name, objectID)
        case let .generated(sequence):
            "generated:\(sequence)"
        }
    }
}

/// Hands out `ReferenceKey.generated` values in order. No clock and no
/// randomness, so the same events give the same keys; saving identity means
/// saving `nextSequence`.
nonisolated public struct GeneratedReferenceAllocator: Hashable, Sendable {
    /// Sequence number the next `allocate()` will hand out. Starts at 1; 0 is
    /// reserved and never allocated, so it stays usable as a sentinel.
    public private(set) var nextSequence: UInt64

    /// Pass a previously saved `nextSequence` to resume allocating where a
    /// restored session left off.
    public init(nextSequence: UInt64 = 1) {
        self.nextSequence = nextSequence
    }

    public mutating func allocate() -> ReferenceKey {
        let sequence = nextSequence
        nextSequence += 1
        return .generated(sequence)
    }
}
