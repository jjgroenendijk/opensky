// Persistent runtime identity for object references. A `FormID` is
// file-relative and a `ResolvedFormID` still carries whatever spelling the
// TES4 MAST field used, so neither is a safe dictionary key across a session.
// `ReferenceKey` normalizes plugin-defined identity and adds a second case for
// objects that no plugin defines, such as dropped items and summons.
//
// Identity rules follow docs/formats/formid.md; nothing here parses input.

import Foundation

/// Session-stable identity of an object reference.
///
/// Two kinds of object exist at runtime. Plugin-defined references come from a
/// loaded plugin and are identified by defining plugin plus 24-bit object ID,
/// matching `ResolvedFormID`. Generated references are created while the game
/// runs and are identified by a sequence number from
/// `GeneratedReferenceAllocator`. The two cases cannot collide, because they
/// are distinct cases of the same enum.
///
/// Total order (`Comparable`), relied on by downstream milestones that need
/// deterministic iteration:
///
/// 1. Every `plugin` key sorts before every `generated` key.
/// 2. `plugin` keys order by plugin name first, using `String`'s `<` over the
///    already-lowercased name, then by `objectID` ascending.
/// 3. `generated` keys order by sequence number ascending.
nonisolated enum ReferenceKey: Hashable, Sendable {
    /// Defining plugin plus low 24 bits of the FormID. The associated `name`
    /// is always lowercased — plugin file names are case-insensitive on the
    /// game's original platform and MAST spelling varies between plugins, so
    /// every construction path normalizes it. Build these through
    /// `init(resolved:)` or `resolve(_:using:)` rather than by hand.
    case plugin(name: String, objectID: UInt32)

    /// Runtime-created reference, sequence-numbered by
    /// `GeneratedReferenceAllocator`.
    case generated(UInt64)

    /// The player, which no plugin reference in this engine stands for.
    ///
    /// Decided in issue #172, because Papyrus needs a stable activator
    /// identity long before an actor record backs the player.
    /// `GeneratedReferenceAllocator` starts at 1 and documents 0 as reserved,
    /// so `.generated(0)` can never collide with an allocated key, sorts after
    /// every plugin key, round-trips through the save file's generated-key tag
    /// unchanged, and needs no plugin to be loaded. The alternative — the
    /// vanilla `Skyrim.esm:000014` player reference — was rejected because it
    /// names a record OpenSky does not decode, would be wrong for any session
    /// whose load order lacks that plugin, and would make the player look like
    /// an ordinary streamed reference the cell builder could try to draw.
    ///
    /// Never write world-state components under this key expecting them to be
    /// drawn: no `RuntimeReferenceEntry` resolves it, so it is an activator
    /// identity and an object-handle identity, nothing more.
    /// Documented in docs/engine/papyrus-vm.md and docs/engine/runtime-state.md.
    static let player = ReferenceKey.generated(0)

    /// Normalizes the resolved plugin name to lowercase.
    init(resolved: ResolvedFormID) {
        self = .plugin(name: resolved.plugin.lowercased(), objectID: resolved.objectID)
    }

    /// Resolves a file-relative FormID against its owning plugin's master
    /// list. Nil for the null FormID, which means "no reference".
    static func resolve(_ id: FormID, using resolver: FormIDResolver) -> ReferenceKey? {
        guard let resolved = resolver.resolve(id) else { return nil }
        return ReferenceKey(resolved: resolved)
    }
}

nonisolated extension ReferenceKey: Comparable {
    static func < (lhs: ReferenceKey, rhs: ReferenceKey) -> Bool {
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
    var description: String {
        switch self {
        case let .plugin(name, objectID):
            String(format: "%@:%06X", name, objectID)
        case let .generated(sequence):
            "generated:\(sequence)"
        }
    }
}

/// Hands out `ReferenceKey.generated` values in order.
///
/// The allocator is deliberately dumb: no timestamps, no randomness, no global
/// state. Given the same sequence of allocation events it produces the same
/// keys, which is what makes a saved game reproducible. Its entire state is
/// `nextSequence`, so saving identity means saving that one number and
/// restoring means passing it back to `init(nextSequence:)`.
nonisolated struct GeneratedReferenceAllocator: Hashable, Sendable {
    /// Sequence number the next `allocate()` will hand out. Starts at 1; 0 is
    /// reserved and never allocated, so it stays usable as a sentinel.
    private(set) var nextSequence: UInt64

    /// Pass a previously saved `nextSequence` to resume allocating where a
    /// restored session left off.
    init(nextSequence: UInt64 = 1) {
        self.nextSequence = nextSequence
    }

    mutating func allocate() -> ReferenceKey {
        let sequence = nextSequence
        nextSequence += 1
        return .generated(sequence)
    }
}
