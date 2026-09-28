// The part of `ActorValueIdentity` that names the runtime's typed primaries. The
// name table lives with the record parsers in OpenSkyFormats; `ActorValueKind`
// is runtime state, so this mapping stays in the engine.

import OpenSkyFormats

nonisolated extension ActorValueIdentity {
    /// Index of each value the runtime stores, per `vanillaNames`.
    static let storedIndices: [ActorValueKind: Int32] = [
        .health: 24, .magicka: 25, .stamina: 26
    ]

    /// The *primary* value `index` names, or nil for every other index in the
    /// table and for an index outside it alike.
    ///
    /// Since 19.5 this is a fast-path question, not a can-I-read-it question:
    /// nil means "goes through the general table", and `isVanilla(index:)` is
    /// what says whether the index names an actor value at all.
    static func kind(at index: Int32) -> ActorValueKind? {
        kindsByIndex[index]
    }

    /// Vanilla index of one of the three primaries, which is the inverse of
    /// `kind(at:)` and is what lets a primary be addressed through the same
    /// index-keyed override table as every other actor value (issue #496).
    ///
    /// `storedIndices` names all three, so the fallback is unreachable; it is
    /// `noneIndex` rather than a force-unwrap because an index outside the
    /// table is already the documented miss everything here answers with.
    static func index(of kind: ActorValueKind) -> Int32 {
        storedIndices[kind] ?? noneIndex
    }

    /// The stored value `name` spells, by the same rule as `kind(at:)`.
    static func kind(named name: String) -> ActorValueKind? {
        guard let index = index(named: name) else { return nil }
        return kind(at: index)
    }

    private static let kindsByIndex: [Int32: ActorValueKind] = storedIndices
        .reduce(into: [:]) { table, entry in table[entry.value] = entry.key }
}
