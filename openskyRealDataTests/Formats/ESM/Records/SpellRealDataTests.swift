// Env-gated SPEL and SCRL sweep over the user's read-only active load order.
// Decodes every spell and scroll definition, pins a handful of vanilla
// identities by editor ID, and compares the auto-calculated cost against the
// cost the SPIT struct stores.

import Foundation
@testable import opensky
import Testing

struct SpellRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func decodesEverySpellAndScrollAndReconcilesTheirCosts() throws {
        let root = try #require(Self.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let index = RecordIndex(plugins: plugins, recordTypes: ["MGEF", "SPEL", "SCRL"])
        let spellDefinitions = index.definitions(of: "SPEL")
        let scrollDefinitions = index.definitions(of: "SCRL")
        var tally = SweepTally()

        for indexed in spellDefinitions {
            try tally.record(sizesIn: indexed.record)
            try tally.note(Spell(record: indexed.record, localized: indexed.localized))
        }
        for indexed in scrollDefinitions {
            try tally.record(sizesIn: indexed.record)
            try tally.note(Scroll(record: indexed.record, localized: indexed.localized))
        }

        #expect(spellDefinitions.count >= 1440)
        #expect(scrollDefinitions.count >= 102)
        #expect(tally.decodedCount == spellDefinitions.count + scrollDefinitions.count)
        #expect(tally.spitSizes.keys.allSatisfy { $0 >= 36 })
        #expect(tally.malformedFieldCount == 0)
        #expect(tally.unknownEnumCount == 0)

        let store = SpellStore(index: index)
        #expect(store.spells.count >= 1440)
        #expect(store.scrolls.count >= 102)
        try expectVanillaPins(in: store)

        // An auto-calculated record's stored SPIT cost is a cache of the same
        // formula, so agreement is the expected case. It is not universal:
        // some vanilla records store a value the effect list alone does not
        // reproduce, which is why this asserts a floor on the agreeing share
        // rather than demanding every record match.
        let costs = CostReconciliation(store: store)
        #expect(costs.autoCalculated > 0)
        #expect(costs.mismatches.count * 5 <= costs.autoCalculated)

        report(
            spells: spellDefinitions.count,
            scrolls: scrollDefinitions.count,
            store: store,
            tally: tally,
            costs: costs
        )
    }

    /// One vanilla spell pinned by identity, casting header and effect list.
    private struct Pin {
        let editorID: String
        let objectID: UInt32
        let castingType: MagicEffectCastingType
        let delivery: MagicEffectDelivery
        let effects: [String]
    }

    private func expectVanillaPins(in store: SpellStore) throws {
        let pins = [
            Pin(
                editorID: "Flames",
                objectID: 0x012FCD,
                castingType: .concentration,
                delivery: .aimed,
                effects: ["FireDamageConcAimed", "PerkIntenseFlamesConfDownConcAimed"]
            ),
            Pin(
                editorID: "Healing",
                objectID: 0x012FCC,
                castingType: .concentration,
                delivery: .selfTarget,
                effects: ["RestoreHealthConcSelf", "PerkRestoreStaminaConcSelf"]
            ),
            Pin(
                editorID: "Firebolt",
                objectID: 0x012FD0,
                castingType: .fireAndForget,
                delivery: .aimed,
                effects: [
                    "FireDamageFFAimed",
                    "PerkImpactStaggerPushFFAimed",
                    "PerkIntenseFlamesConfDownFFAimed"
                ]
            )
        ]
        for pin in pins {
            let spell = try #require(store.spell(editorID: pin.editorID))
            #expect(spell.editorID == pin.editorID)
            #expect(spell.id == ResolvedFormID(plugin: "Skyrim.esm", objectID: pin.objectID))
            #expect(spell.record.data?.castingType == pin.castingType)
            #expect(spell.record.data?.delivery == pin.delivery)
            #expect(spell.effects.compactMap(\.effect?.effect.editorID) == pin.effects)
        }
    }

    private func report(
        spells: Int,
        scrolls: Int,
        store: SpellStore,
        tally: SweepTally,
        costs: CostReconciliation
    ) {
        print(
            "[INFO] SPEL definitions \(spells), "
                + "SCRL definitions \(scrolls), "
                + "winning spells \(store.spells.count), scrolls \(store.scrolls.count), "
                + "SPIT sizes \(tally.spitSizes.keys.sorted()), "
                + "unread fields \(tally.unreadFieldCount) "
                + "\(tally.unreadFields.sorted { $0.key < $1.key }), "
                + "malformed fields \(tally.malformedFieldCount), "
                + "unknown enums \(tally.unknownEnumCount), "
                + "manual-cost records \(costs.manual), "
                + "auto-calc records \(costs.autoCalculated), "
                + "cost mismatches \(costs.mismatches.count), "
                + "worst \(costs.worst.map(\.description) ?? "none")"
        )
    }

    // MARK: - Tallies

    private struct SweepTally {
        var decodedCount = 0
        var unreadFieldCount = 0
        var malformedFieldCount = 0
        var unknownEnumCount = 0
        var spitSizes: [Int: Int] = [:]
        /// Which field types went unread, so a gap shows up as a name rather
        /// than as a number.
        var unreadFields: [String: Int] = [:]

        mutating func record(sizesIn record: ESMRecord) throws {
            for field in try record.fields() where field.type == "SPIT" {
                spitSizes[field.data.count, default: 0] += 1
            }
        }

        mutating func note(_ spell: Spell) {
            note(.spell(spell))
        }

        mutating func note(_ scroll: Scroll) {
            note(.scroll(scroll))
        }

        private mutating func note(_ record: MagicCastingRecord) {
            decodedCount += 1
            unreadFieldCount += record.skipped.total
            for (kind, count) in record.skipped.counts {
                switch kind {
                case let .malformedField(type):
                    malformedFieldCount += count
                    unreadFields["\(type) malformed", default: 0] += count
                case let .unknownField(type):
                    unreadFields["\(type)", default: 0] += count
                }
            }
            unknownEnumCount += record.data?.unknownEnumCount ?? 0
        }
    }

    /// The stored SPIT cost against the cost recomputed from the effect list.
    private struct CostReconciliation {
        struct Mismatch: CustomStringConvertible {
            let editorID: String
            let stored: UInt32
            let computed: UInt32

            var description: String {
                "\(editorID) stored \(stored) computed \(computed)"
            }
        }

        private(set) var manual = 0
        private(set) var autoCalculated = 0
        private(set) var mismatches: [Mismatch] = []

        var worst: Mismatch? {
            mismatches.max { left, right in
                difference(left) < difference(right)
            }
        }

        init(store: SpellStore) {
            for spell in store.records.values {
                guard let data = spell.record.data else { continue }
                guard data.usesAutoCalculatedCost else {
                    manual += 1
                    continue
                }
                autoCalculated += 1
                let computed = spell.cost.cost
                guard computed != data.baseCost else { continue }
                mismatches.append(Mismatch(
                    editorID: spell.editorID ?? "-",
                    stored: data.baseCost,
                    computed: computed
                ))
            }
        }

        private func difference(_ mismatch: Mismatch) -> UInt32 {
            mismatch.stored > mismatch.computed
                ? mismatch.stored - mismatch.computed
                : mismatch.computed - mismatch.stored
        }
    }
}
