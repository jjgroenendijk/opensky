// Env-gated ENCH sweep over the user's read-only active load order. Decodes
// every enchantment definition, pins a handful of vanilla identities by editor
// ID, and reports how many weapons and pieces of armor carry an EITM link and
// how many of those links resolve.

import Foundation
@testable import opensky
import Testing

struct EnchantmentRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func decodesEveryEnchantmentAndResolvesTheItemLinks() throws {
        let root = try #require(Self.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let index = RecordIndex(
            plugins: plugins,
            recordTypes: ["MGEF", "ENCH", "WEAP", "ARMO"]
        )
        let definitions = index.definitions(of: "ENCH")
        var tally = SweepTally()
        for indexed in definitions {
            try tally.record(sizesIn: indexed.record)
            try tally.note(Enchantment(record: indexed.record, localized: indexed.localized))
        }

        #expect(definitions.count >= 752)
        #expect(tally.decodedCount == definitions.count)
        #expect(tally.enitSizes.keys.allSatisfy { $0 >= EnchantmentItemData.minimumSize })
        #expect(tally.malformedFieldCount == 0)
        #expect(tally.unknownEnumCount == 0)

        let store = EnchantmentStore(index: index)
        #expect(store.enchantments.count >= 700)
        try expectVanillaPins(in: store)

        let links = ItemLinkTally(index: index, store: store)
        #expect(links.weaponsWithLink > 0)
        #expect(links.armorWithLink > 0)
        #expect(links.unresolvedWeapons == 0)
        #expect(links.unresolvedArmor == 0)
        #expect(links.longestChain >= 1)

        report(definitions: definitions.count, store: store, tally: tally, links: links)
    }

    /// One vanilla enchantment pinned by identity, header, effect list and the
    /// length of the base chain above it. Every value here was read off this
    /// machine's install, not from memory.
    private struct Pin {
        let editorID: String
        let objectID: UInt32
        let type: EnchantmentType
        let delivery: MagicEffectDelivery
        let effects: [String]
        let chainLength: Int
    }

    private func expectVanillaPins(in store: EnchantmentStore) throws {
        let pins = [
            Pin(
                editorID: "EnchYsgramorShield",
                objectID: 0x0001_7299,
                type: .enchantment,
                delivery: .selfTarget,
                effects: ["EnchResistMagicConstantSelf", "EnchFortifyHealthConstantSelf"],
                // This one derives from a base enchantment, so its chain is two
                // entries long where most are one.
                chainLength: 2
            ),
            Pin(
                editorID: "StaffEnchFireball",
                objectID: 0x0002_9B59,
                type: .staffEnchantment,
                delivery: .aimed,
                effects: ["FireDamageFFAimedArea"],
                chainLength: 1
            ),
            Pin(
                editorID: "StaffEnchParalyze",
                objectID: 0x0002_9B4A,
                type: .staffEnchantment,
                delivery: .aimed,
                effects: ["ParalysisFFAimed", "StaggerPushFFAimed"],
                chainLength: 1
            )
        ]
        for pin in pins {
            let enchantment = try #require(store.enchantment(editorID: pin.editorID))
            #expect(enchantment.editorID == pin.editorID)
            #expect(
                enchantment.id == ResolvedFormID(plugin: "Skyrim.esm", objectID: pin.objectID)
            )
            #expect(enchantment.data?.type == pin.type)
            #expect(enchantment.data?.delivery == pin.delivery)
            #expect(enchantment.effects.compactMap(\.effect?.effect.editorID) == pin.effects)
            #expect(store.baseChain(of: enchantment.id).count == pin.chainLength)
        }
    }

    private func report(
        definitions: Int,
        store: EnchantmentStore,
        tally: SweepTally,
        links: ItemLinkTally
    ) {
        print(
            "[INFO] ENCH definitions \(definitions), "
                + "winning enchantments \(store.enchantments.count), "
                + "ENIT sizes \(tally.enitSizes.sorted { $0.key < $1.key }), "
                + "unread fields \(tally.unreadFieldCount) "
                + "\(tally.unreadFields.sorted { $0.key < $1.key }), "
                + "malformed fields \(tally.malformedFieldCount), "
                + "unknown enums \(tally.unknownEnumCount), "
                + "manual-cost records \(tally.manualCost), "
                + "base-enchantment links \(tally.withBaseEnchantment), "
                + "worn-restriction links \(tally.withWornRestrictions), "
                + "longest base chain \(links.longestChain), "
                + "WEAP with EITM \(links.weaponsWithLink) "
                + "(\(links.unresolvedWeapons) unresolved), "
                + "ARMO with EITM \(links.armorWithLink) "
                + "(\(links.unresolvedArmor) unresolved)"
        )
    }

    // MARK: - Tallies

    private struct SweepTally {
        var decodedCount = 0
        var unreadFieldCount = 0
        var malformedFieldCount = 0
        var unknownEnumCount = 0
        var manualCost = 0
        var withBaseEnchantment = 0
        var withWornRestrictions = 0
        var enitSizes: [Int: Int] = [:]
        /// Which field types went unread, so a gap shows up as a name rather
        /// than as a number.
        var unreadFields: [String: Int] = [:]

        mutating func record(sizesIn record: ESMRecord) throws {
            for field in try record.fields() where field.type == "ENIT" {
                enitSizes[field.data.count, default: 0] += 1
            }
        }

        mutating func note(_ enchantment: Enchantment) {
            decodedCount += 1
            unreadFieldCount += enchantment.skipped.total
            for (kind, count) in enchantment.skipped.counts {
                switch kind {
                case let .malformedField(type):
                    malformedFieldCount += count
                    unreadFields["\(type) malformed", default: 0] += count
                case let .unknownField(type):
                    unreadFields["\(type)", default: 0] += count
                }
            }
            guard let data = enchantment.data else { return }
            unknownEnumCount += data.unknownEnumCount
            if !data.usesAutoCalculatedCost {
                manualCost += 1
            }
            if data.baseEnchantment != nil {
                withBaseEnchantment += 1
            }
            if data.wornRestrictions != nil {
                withWornRestrictions += 1
            }
        }
    }

    /// Every WEAP and ARMO EITM in the load order, against the store.
    private struct ItemLinkTally {
        private(set) var weaponsWithLink = 0
        private(set) var unresolvedWeapons = 0
        private(set) var armorWithLink = 0
        private(set) var unresolvedArmor = 0
        private(set) var longestChain = 0

        init(index: RecordIndex, store: EnchantmentStore) {
            for indexed in index.definitions(of: "WEAP") {
                guard
                    let weapon = try? Weapon(
                        record: indexed.record,
                        localized: indexed.localized
                    ),
                    let link = weapon.enchantment
                else { continue }
                weaponsWithLink += 1
                note(link, from: indexed.sourcePlugin, store: store, weapon: true)
            }
            for indexed in index.definitions(of: "ARMO") {
                guard
                    let armor = try? Armor(
                        record: indexed.record,
                        localized: indexed.localized
                    ),
                    let link = armor.enchantment
                else { continue }
                armorWithLink += 1
                note(link, from: indexed.sourcePlugin, store: store, weapon: false)
            }
        }

        private mutating func note(
            _ link: FormID,
            from plugin: String,
            store: EnchantmentStore,
            weapon: Bool
        ) {
            guard let resolved = store.resolve(link, fromPlugin: plugin) else {
                if weapon {
                    unresolvedWeapons += 1
                } else {
                    unresolvedArmor += 1
                }
                return
            }
            longestChain = max(longestChain, store.baseChain(of: resolved.id).count)
        }
    }
}
