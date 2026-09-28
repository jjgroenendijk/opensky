// Synthetic PerkStore coverage: cross-plugin override, the spell join, the
// NNAM rank chain, and the flat entry-point index the perk runtime queries.

import Foundation
@testable import opensky
import Testing

struct PerkStoreTests {
    @Test
    func laterOverrideWinsAndEditorLookupIsCaseInsensitive() throws {
        let base = try PerkFixture.plugin(perks: [
            PerkFixture.perkRecord(
                formID: 0x42,
                fields: PerkFixture.fields(editorID: "Armsman", name: "Armsman")
            )
        ])
        let patch = try PerkFixture.plugin(
            masters: ["Base.esm"],
            perks: [PerkFixture.perkRecord(
                formID: 0x42,
                fields: PerkFixture.fields(
                    editorID: "ArmsmanPatched",
                    name: "Armsman Revised",
                    header: PerkFixture.header(level: 30, rankCount: 5)
                )
            )]
        )
        let store = PerkStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])

        let resolved = try #require(store.perk(ResolvedFormID(plugin: "Base.esm", objectID: 0x42)))
        #expect(resolved.editorID == "ArmsmanPatched")
        #expect(resolved.displayName == "Armsman Revised")
        #expect(resolved.sourcePlugin == "Patch.esp")
        #expect(resolved.declaredRankCount == 5)
        #expect(store.perk(editorID: "armsmanpatched")?.id == resolved.id)
        #expect(store.perk(editorID: "Armsman") == nil)
    }

    @Test
    func joinsAbilityAndSelectedSpellsAgainstTheSpellStore() throws {
        let plugin = try PerkFixture.plugin(
            perks: [PerkFixture.perkRecord(
                formID: 0x10,
                fields: PerkFixture.fields(
                    editorID: "SpellPerk",
                    effects: [
                        PerkFixture.abilityEffect(spell: 0x01),
                        PerkFixture.entryPointEffect(
                            entryPoint: 51,
                            function: 10,
                            tabs: [(runOn: 0, conditions: [])],
                            functionType: 5,
                            functionData: PerkFixture.word(0x02)
                        ),
                        PerkFixture.entryPointEffect(
                            entryPoint: 51,
                            function: 10,
                            tabs: [(runOn: 0, conditions: [])],
                            functionType: 5,
                            functionData: PerkFixture.word(0x0BAD)
                        )
                    ]
                )
            )],
            spells: [
                PerkFixture.spellRecord(formID: 0x01, editorID: "AbilityFF", name: "Fire Cloak"),
                PerkFixture.spellRecord(formID: 0x02, editorID: "HitFF", name: "Frost Bite")
            ]
        )
        let store = PerkStore(plugins: [("Base.esm", plugin)])
        let perk = try #require(store.perk(editorID: "SpellPerk"))

        #expect(perk.effects[0].spell?.displayName == "Fire Cloak")
        #expect(perk.effects[0].spellName == "Fire Cloak")
        #expect(perk.effects[1].spell?.displayName == "Frost Bite")
        // A link no record answers stays visible as unresolved rather than
        // silently reading as "this effect casts nothing".
        #expect(perk.effects[2].spell == nil)
        #expect(perk.effects[2].spellName?.hasPrefix("[UNRESOLVED]") == true)
    }

    @Test
    func followsTheNextPerkRankChainAndStopsOnALoop() throws {
        let plugin = try PerkFixture.plugin(perks: [
            rank(formID: 0x20, editorID: "Rank1", ranks: 3, next: 0x21),
            rank(formID: 0x21, editorID: "Rank2", ranks: 3, next: 0x22),
            rank(formID: 0x22, editorID: "Rank3", ranks: 3, next: nil),
            rank(formID: 0x30, editorID: "LoopA", ranks: 2, next: 0x31),
            rank(formID: 0x31, editorID: "LoopB", ranks: 2, next: 0x30)
        ])
        let store = PerkStore(plugins: [("Base.esm", plugin)])
        let first = try #require(store.perk(editorID: "Rank1"))

        #expect(store.rankChain(from: first.id).map(\.editorID) == ["Rank1", "Rank2", "Rank3"])
        #expect(first.nextPerk == ResolvedFormID(plugin: "Base.esm", objectID: 0x21))
        #expect(store.rankChain(from: first.id).count == Int(first.declaredRankCount))

        let loop = try #require(store.perk(editorID: "LoopA"))
        #expect(store.rankChain(from: loop.id).map(\.editorID) == ["LoopA", "LoopB"])
    }

    @Test
    func indexesEveryEntryPointEffectAcrossPerks() throws {
        let plugin = try PerkFixture.plugin(perks: [
            PerkFixture.perkRecord(
                formID: 0x40,
                fields: PerkFixture.fields(
                    editorID: "DamagePerkLow",
                    effects: [entryPoint(35, priority: 1), entryPoint(0, priority: 0)]
                )
            ),
            PerkFixture.perkRecord(
                formID: 0x41,
                fields: PerkFixture.fields(
                    editorID: "DamagePerkHigh",
                    effects: [entryPoint(35, priority: 9)]
                )
            )
        ])
        let store = PerkStore(plugins: [("Base.esm", plugin)])

        let attackDamage = store.matches(at: PerkEntryPoint(rawValue: 35))
        #expect(attackDamage.count == 2)
        // Highest PRKE priority first, which is the order the runtime applies.
        #expect(attackDamage.map(\.priority) == [9, 1])
        #expect(attackDamage[0].perk == ResolvedFormID(plugin: "Base.esm", objectID: 0x41))

        let effect = try #require(store.effect(attackDamage[0]))
        #expect(effect.entryPoint == PerkEntryPoint(rawValue: 35))
        #expect(effect.effect.functionData == .float(1.5))

        #expect(store.matches(at: PerkEntryPoint(rawValue: 0)).count == 1)
        // An entry point nothing hooks answers empty rather than nil, so a
        // formula can query it without a special case.
        #expect(store.matches(at: PerkEntryPoint(rawValue: 91)).isEmpty)

        #expect(store.entryPointHistogram.map(\.count) == [2, 1])
        #expect(store.entryPointHistogram[0].entryPoint == PerkEntryPoint(rawValue: 35))
    }

    @Test
    func resolvesLinksRelativeToTheAuthoringPlugin() throws {
        let base = try PerkFixture.plugin(perks: [PerkFixture.perkRecord(
            formID: 1,
            fields: PerkFixture.fields(editorID: "Armsman", name: "Armsman")
        )])
        let patch = try PerkFixture.plugin(masters: ["Base.esm"])
        let store = PerkStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])

        #expect(store.resolve(FormID(1), fromPlugin: "Base.esm")?.editorID == "Armsman")
        #expect(store.displayString(for: FormID(1), fromPlugin: "Base.esm") == "Armsman")
        #expect(
            store.displayString(for: FormID(0x0BAD), fromPlugin: "Base.esm")
                .hasPrefix("[UNRESOLVED]")
        )
    }

    private func rank(
        formID: UInt32,
        editorID: String,
        ranks: UInt8,
        next: UInt32?
    ) -> Data {
        PerkFixture.perkRecord(formID: formID, fields: PerkFixture.fields(
            editorID: editorID,
            header: PerkFixture.header(rankCount: ranks),
            nextPerk: next
        ))
    }

    private func entryPoint(_ id: UInt8, priority: UInt8) -> Data {
        PerkFixture.entryPointEffect(
            entryPoint: id,
            function: 3,
            priority: priority,
            tabs: [(runOn: 0, conditions: [])],
            functionType: 1,
            functionData: PerkFixture.float(1.5)
        )
    }
}
