// The part of `ActorValueIdentity` that names the runtime's typed primaries. The
// name table lives with the record parsers in OpenSkyFormatsESM; `ActorValueKind`
// is runtime state, so this mapping stays in the engine.

import OpenSkyFormatsESM

nonisolated extension ActorValueIdentity {
    /// Index of each value the runtime stores, per `vanillaNames`.
    public static let storedIndices: [ActorValueKind: Int32] = [
        .health: 24, .magicka: 25, .stamina: 26
    ]

    /// The *primary* value `index` names, or nil for every other index in the
    /// table and for an index outside it alike.
    ///
    /// Since 19.5 this is a fast-path question, not a can-I-read-it question:
    /// nil means "goes through the general table", and `isVanilla(index:)` is
    /// what says whether the index names an actor value at all.
    public static func kind(at index: Int32) -> ActorValueKind? {
        kindsByIndex[index]
    }

    /// Table index of a primary: the inverse of `kind(at:)`, so primaries share the
    /// index-keyed override table. The `noneIndex` fallback is unreachable.
    public static func index(of kind: ActorValueKind) -> Int32 {
        storedIndices[kind] ?? noneIndex
    }

    /// The stored value `name` spells, by the same rule as `kind(at:)`.
    public static func kind(named name: String) -> ActorValueKind? {
        guard let index = index(named: name) else { return nil }
        return kind(at: index)
    }

    private static let kindsByIndex: [Int32: ActorValueKind] = storedIndices
        .reduce(into: [:]) { table, entry in table[entry.value] = entry.key }
}
