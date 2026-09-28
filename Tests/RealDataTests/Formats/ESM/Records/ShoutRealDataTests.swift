// Env-gated SHOU / WOOP / LVSP / DUAL / EQUP sweep over the user's read-only
// active load order (issue #467). Decodes every record of all five types, pins
// one vanilla shout by identity, and checks that every WEAP and SPEL ETYP in
// the load order resolves to an EQUP.

import Foundation
@testable import opensky
import Testing

struct ShoutRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// Counts observed in this machine's active load order when the sweep was
    /// written. Asserted as floors so a load order with more plugins still
    /// passes; the masters alone supply these.
    private enum Floor {
        static let shouts = 117
        static let words = 107
        static let leveledSpells = 33
        static let dualCastData = 2
        static let equipSlots = 7
    }

    @Test(.enabled(if: Self.dataRoot != nil))
    func decodesEveryShoutFamilyRecord() throws {
        let root = try #require(Self.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let index = RecordIndex(
            plugins: plugins,
            recordTypes: ["MGEF", "SPEL", "SHOU", "WOOP", "LVSP", "DUAL", "EQUP"]
        )

        var wordEntryCount = 0
        var skipped = 0
        let shouts = index.definitions(of: "SHOU")
        for indexed in shouts {
            let shout = try Shout(record: indexed.record, localized: indexed.localized)
            wordEntryCount += shout.words.count
            skipped += shout.skipped.total
        }
        let words = try index.definitions(of: "WOOP").map {
            try WordOfPower(record: $0.record, localized: $0.localized)
        }
        let leveled = try index.definitions(of: "LVSP").map { try LeveledList(record: $0.record) }
        let duals = try index.definitions(of: "DUAL").map { try DualCastData(record: $0.record) }
        let slots = try index.definitions(of: "EQUP").map { try EquipSlot(record: $0.record) }

        #expect(shouts.count >= Floor.shouts)
        #expect(words.count >= Floor.words)
        #expect(leveled.count >= Floor.leveledSpells)
        #expect(duals.count >= Floor.dualCastData)
        #expect(slots.count >= Floor.equipSlots)
        // Every vanilla shout stores exactly three SNAM entries, including the
        // powers that are not really shouts.
        #expect(wordEntryCount == shouts.count * 3)
        #expect(skipped == 0)
        #expect(words.allSatisfy { $0.translation != nil })
        #expect(leveled.allSatisfy { $0.recordType == "LVSP" })
        #expect(duals.allSatisfy { $0.art != nil })
        #expect(slots.allSatisfy { $0.skipped.total == 0 })

        report(
            shouts: shouts.count,
            words: words.count,
            leveled: leveled.count,
            duals: duals.count,
            slots: slots.count
        )
    }

    @Test(.enabled(if: Self.dataRoot != nil))
    func aPinnedShoutResolvesItsThreeWordsAndSpells() throws {
        let root = try #require(Self.dataRoot)
        let store = ShoutStoreLoader.load(root: root)
        let shout = try #require(store.shout(editorID: "FireBreathShout"))

        #expect(shout.id.objectID == 0x03F9EA)
        #expect(shout.words.count == 3)
        #expect(shout.words.allSatisfy { $0.word != nil })
        #expect(shout.words.allSatisfy { $0.spell != nil })
        #expect(
            shout.words.compactMap { $0.word?.editorID }
                == ["WordYol", "WordToor", "WordShul"]
        )
        #expect(
            shout.words.compactMap { $0.spell?.editorID }
                == ["VoiceFireBreath1", "VoiceFireBreath2", "VoiceFireBreath3"]
        )
        // Recovery time is the total recharge after each word is learned, so
        // it rises across the three entries.
        #expect(shout.words.map(\.entry.recoveryTime) == [30, 50, 100])
    }

    @Test(.enabled(if: Self.dataRoot != nil))
    func everyWeaponAndSpellEquipTypeResolvesToAnEquipSlot() throws {
        let root = try #require(Self.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let index = RecordIndex(
            plugins: plugins,
            recordTypes: ["MGEF", "SPEL", "WEAP", "EQUP"]
        )
        let slots = EquipSlotStore(index: index)
        var weapons = LinkCounts()
        var spells = LinkCounts()

        for indexed in index.definitions(of: "WEAP") {
            let weapon = try Weapon(record: indexed.record, localized: indexed.localized)
            weapons.note(
                link: weapon.equipType,
                hands: slots.hands(of: weapon.equipType, fromPlugin: indexed.sourcePlugin)
            )
        }
        for indexed in index.definitions(of: "SPEL") {
            let spell = try Spell(record: indexed.record, localized: indexed.localized)
            let link = spell.header.equipType
            spells.note(
                link: link,
                hands: slots.hands(of: link, fromPlugin: indexed.sourcePlugin)
            )
        }

        // Every authored link resolves; the only misses are records that carry
        // no ETYP at all, which fall back on the documented default.
        #expect(weapons.unresolvedLinks == 0)
        #expect(spells.unresolvedLinks == 0)
        #expect(weapons.resolved > 0)
        #expect(spells.resolved > 0)

        print(
            "[INFO] ETYP resolution — weapons: \(weapons.resolved) resolved, "
                + "\(weapons.absent) without ETYP, "
                + "\(weapons.unresolvedLinks) dangling; "
                + "spells: \(spells.resolved) resolved, "
                + "\(spells.absent) without ETYP, "
                + "\(spells.unresolvedLinks) dangling"
        )
    }

    /// Resolved, absent and dangling counts for one record type's ETYP links.
    private struct LinkCounts {
        var resolved = 0
        /// The record carries no ETYP; the caller applies its default.
        var absent = 0
        /// The record names an EQUP nothing in the load order defines.
        var unresolvedLinks = 0

        mutating func note(link: FormID?, hands: HandSlots?) {
            guard let link, !link.isNull else {
                absent += 1
                return
            }
            if hands == nil {
                unresolvedLinks += 1
            } else {
                resolved += 1
            }
        }
    }

    private func report(shouts: Int, words: Int, leveled: Int, duals: Int, slots: Int) {
        print(
            "[INFO] shout family — SHOU \(shouts), WOOP \(words), LVSP \(leveled), "
                + "DUAL \(duals), EQUP \(slots)"
        )
    }
}
