// Load-order-wide ENCH lookup above RecordIndex, like `SpellStore`. It joins each
// effect with `MagicEffectStore` and computes the auto-calculated cost once,
// through `SpellCost`. It follows the base-enchantment chain, with a cycle guard.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct ResolvedEnchantment: Sendable {
    public let id: ResolvedFormID
    public let record: Enchantment
    public let sourcePlugin: String
    /// The effect list joined against `MagicEffectStore`, costed once.
    public let effects: [ResolvedSpellEffect]
    public let cost: SpellCostResult

    public var editorID: String? {
        record.editorID
    }

    public var data: EnchantmentItemData? {
        record.data
    }

    public var displayName: String {
        switch record.name {
        case let .inline(value): value
        case let .tableID(id): record.editorID ?? "string #\(id)"
        case nil: record.editorID ?? id.description
        }
    }
}

nonisolated public struct EnchantmentStore: Sendable {
    /// Bounds a base-enchantment chain that a mod has made cyclic or absurdly
    /// deep. Vanilla chains are one link long.
    public static let chainCap = 32

    private let index: RecordIndex
    /// Every winning ENCH identity in the load order.
    public private(set) var enchantments: [ResolvedFormID: ResolvedEnchantment] = [:]
    private var enchantmentsByEditorID: [String: ResolvedEnchantment] = [:]

    public init(index: RecordIndex, effects: MagicEffectStore) {
        self.index = index
        let orderedIDs = index.records.keys.sorted {
            RecordStoreOrdering.precedes($0, $1, index: index)
        }
        for id in orderedIDs {
            guard index.records[id]?.record.type == "ENCH" else { continue }
            guard
                case let .decoded(decoded, sourcePlugin) = index.decodeIndexed(
                    id,
                    using: Self.decode
                )
            else { continue }
            let resolved = Self.join(
                id: id,
                record: decoded,
                sourcePlugin: sourcePlugin,
                effects: effects
            )
            enchantments[id] = resolved
            if let editorID = decoded.editorID {
                enchantmentsByEditorID[editorID.lowercased()] = resolved
            }
        }
    }

    public init(index: RecordIndex) {
        self.init(index: index, effects: MagicEffectStore(index: index))
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["MGEF", "ENCH"]))
    }

    public func enchantment(_ id: ResolvedFormID) -> ResolvedEnchantment? {
        enchantments[id] ?? enchantments.first { key, _ in
            key.objectID == id.objectID
                && key.plugin.caseInsensitiveCompare(id.plugin) == .orderedSame
        }?.value
    }

    public func enchantment(editorID: String) -> ResolvedEnchantment? {
        enchantmentsByEditorID[editorID.lowercased()]
    }

    public func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard case let .resolved(resolvedID) = index.resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return resolvedID
    }

    public func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedEnchantment? {
        guard let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return enchantment(resolvedID)
    }

    public func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.displayName ?? "[UNRESOLVED] \(id)"
    }

    /// The requested enchantment followed by each base enchantment above it,
    /// nearest first. A link that does not resolve ends the chain, and an
    /// identity already in the chain is dropped rather than followed, so a
    /// cyclic mod chain terminates instead of recursing.
    public func baseChain(of id: ResolvedFormID) -> [ResolvedEnchantment] {
        guard let start = enchantment(id) else { return [] }
        var chain = [start]
        var seen: Set<ResolvedFormID> = [start.id]
        var current = start
        while chain.count < Self.chainCap {
            guard
                let link = current.data?.baseEnchantment,
                let next = resolve(link, fromPlugin: current.sourcePlugin),
                seen.insert(next.id).inserted
            else { break }
            chain.append(next)
            current = next
        }
        return chain
    }

    /// Joins one record's effect list against the effect store. Exposed so a
    /// caller holding an already-decoded record — the text dump, which decodes
    /// the record in front of it — gets the same numbers the store holds.
    public static func resolvedEffects(
        of record: Enchantment,
        fromPlugin pluginName: String,
        effects store: MagicEffectStore
    ) -> [ResolvedSpellEffect] {
        let castingType = record.data?.castingType ?? .fireAndForget
        return record.effects.map { item in
            let resolved = store.resolve(item, fromPlugin: pluginName)
            let baseCost = resolved?.effect.data?.baseCost
            return ResolvedSpellEffect(
                item: item,
                effect: resolved,
                cost: baseCost.map {
                    SpellCost.effectCost(
                        baseCost: $0,
                        magnitude: item.magnitude,
                        duration: item.duration,
                        castingType: castingType
                    )
                } ?? 0
            )
        }
    }

    /// Totals joined effects into the cost the enchantment charges per use.
    public static func cost(
        of record: Enchantment,
        effects: [ResolvedSpellEffect]
    ) -> SpellCostResult {
        let data = record.data
        return SpellCost.result(
            isManual: data?.flags.contains(.manualCostCalc) ?? false,
            authoredCost: UInt32(max(data?.cost ?? 0, 0)),
            total: SpellCost.total(ofEffectCosts: effects.map(\.cost)),
            unresolvedEffects: effects.count { $0.effect == nil }
        )
    }

    private static func join(
        id: ResolvedFormID,
        record: Enchantment,
        sourcePlugin: String,
        effects store: MagicEffectStore
    ) -> ResolvedEnchantment {
        let resolvedEffects = resolvedEffects(
            of: record,
            fromPlugin: sourcePlugin,
            effects: store
        )
        return ResolvedEnchantment(
            id: id,
            record: record,
            sourcePlugin: sourcePlugin,
            effects: resolvedEffects,
            cost: cost(of: record, effects: resolvedEffects)
        )
    }

    private static func decode(_ indexed: IndexedRecord) throws -> Enchantment {
        try Enchantment(record: indexed.record, localized: indexed.localized)
    }
}
