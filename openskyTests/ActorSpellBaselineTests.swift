// An actor's authored spell list (issue #473, roadmap item 19.10, scope point
// 1): which record in a template chain supplies it, the race list beside it,
// and the leveled spell lists an entry may route through.
//
// Records are synthetic and built in code — never extracted game files
// (AGENTS.md "Legal & IP boundary"). `ActorSpellBaselineRealDataTests` pins the
// same resolution against a vanilla caster.

import Foundation
@testable import opensky
import Testing

struct ActorSpellBaselineTests {
    private enum Form {
        static let wizard: UInt32 = 0x0000_0100
        static let templateWizard: UInt32 = 0x0000_0101
        static let breton: UInt32 = 0x0000_0200
        static let firebolt: UInt32 = 0x0000_0300
        static let iceSpike: UInt32 = 0x0000_0301
        static let heal: UInt32 = 0x0000_0302
        static let racialAbility: UInt32 = 0x0000_0303
        static let boltList: UInt32 = 0x0000_0400
        static let outerList: UInt32 = 0x0000_0401
    }

    // MARK: - The NPC_ list

    @Test func anActorsOwnSpellListIsWhatItKnows() throws {
        let resolver = try ActorSpellFixture.resolver(
            npcs: [ActorSpellFixture.npc(formID: Form.wizard, spells: [Form.firebolt, Form.heal])]
        )

        let baseline = resolver.baseline(for: FormID(Form.wizard))

        #expect(baseline.actorSpells == [FormID(Form.firebolt), FormID(Form.heal)])
        #expect(baseline.raceSpells.isEmpty)
    }

    /// `Use Spell List` is its own ACBS template-data bit, so the list comes
    /// from the template only while that bit is set.
    @Test func theSpellListComesFromTheTemplateWhenUseSpellListIsSet() throws {
        let resolver = try ActorSpellFixture.resolver(npcs: [
            ActorSpellFixture.npc(
                formID: Form.wizard,
                templateFlags: 0x0008,
                template: Form.templateWizard,
                spells: []
            ),
            ActorSpellFixture.npc(formID: Form.templateWizard, spells: [Form.firebolt])
        ])

        let baseline = resolver.baseline(for: FormID(Form.wizard))

        #expect(baseline.actorSpells == [FormID(Form.firebolt)])
    }

    @Test func aLocalEmptyListStaysAuthoritativeWithoutTheFlag() throws {
        let resolver = try ActorSpellFixture.resolver(npcs: [
            ActorSpellFixture.npc(
                formID: Form.wizard,
                template: Form.templateWizard,
                spells: []
            ),
            ActorSpellFixture.npc(formID: Form.templateWizard, spells: [Form.firebolt])
        ])

        #expect(resolver.baseline(for: FormID(Form.wizard)).actorSpells.isEmpty)
    }

    // MARK: - The race list

    @Test func theRaceSpellsRideAlongWithTheActorsOwn() throws {
        let resolver = try ActorSpellFixture.resolver(
            npcs: [ActorSpellFixture.npc(
                formID: Form.wizard, race: Form.breton, spells: [Form.firebolt]
            )],
            races: [ActorSpellFixture.race(formID: Form.breton, spells: [Form.racialAbility])]
        )

        let baseline = resolver.baseline(for: FormID(Form.wizard))

        #expect(baseline.raceSpells == [FormID(Form.racialAbility)])
        #expect(baseline.all == [FormID(Form.firebolt), FormID(Form.racialAbility)])
    }

    @Test func aSpellNamedByBothListsIsKnownOnce() throws {
        let resolver = try ActorSpellFixture.resolver(
            npcs: [ActorSpellFixture.npc(
                formID: Form.wizard, race: Form.breton, spells: [Form.racialAbility]
            )],
            races: [ActorSpellFixture.race(formID: Form.breton, spells: [Form.racialAbility])]
        )

        #expect(resolver.baseline(for: FormID(Form.wizard)).all == [FormID(Form.racialAbility)])
    }

    // MARK: - Leveled spell lists

    /// The finding the real-data suite pins: a caster's attack spells sit
    /// behind an LVSP, and the deterministic policy — highest level, first
    /// among ties — picks the one it ends up knowing.
    @Test func anEntryNamingALeveledSpellListExpandsToOneSpell() throws {
        let resolver = try ActorSpellFixture.resolver(
            npcs: [ActorSpellFixture.npc(formID: Form.wizard, spells: [Form.boltList])],
            leveledSpells: [ActorSpellFixture.lvsp(
                formID: Form.boltList,
                entries: [
                    LeveledList.Entry(level: 1, reference: FormID(Form.firebolt), count: 1),
                    LeveledList.Entry(level: 10, reference: FormID(Form.iceSpike), count: 1)
                ]
            )]
        )

        #expect(resolver.baseline(for: FormID(Form.wizard)).actorSpells == [FormID(Form.iceSpike)])
    }

    @Test func aNestedLeveledSpellListIsFollowedToTheSpell() throws {
        let resolver = try ActorSpellFixture.resolver(
            npcs: [ActorSpellFixture.npc(formID: Form.wizard, spells: [Form.outerList])],
            leveledSpells: [
                ActorSpellFixture.lvsp(
                    formID: Form.outerList,
                    entries: [
                        LeveledList.Entry(level: 1, reference: FormID(Form.boltList), count: 1)
                    ]
                ),
                ActorSpellFixture.lvsp(
                    formID: Form.boltList,
                    entries: [
                        LeveledList.Entry(level: 1, reference: FormID(Form.firebolt), count: 1)
                    ]
                )
            ]
        )

        #expect(resolver.baseline(for: FormID(Form.wizard)).actorSpells == [FormID(Form.firebolt)])
    }

    @Test func aLeveledSpellListPointingAtItselfIsSurvived() throws {
        let resolver = try ActorSpellFixture.resolver(
            npcs: [ActorSpellFixture.npc(formID: Form.wizard, spells: [Form.boltList])],
            leveledSpells: [ActorSpellFixture.lvsp(
                formID: Form.boltList,
                entries: [
                    LeveledList.Entry(level: 1, reference: FormID(Form.boltList), count: 1)
                ]
            )]
        )

        #expect(resolver.baseline(for: FormID(Form.wizard)).actorSpells == [FormID(Form.boltList)])
    }

    @Test func anEmptyLeveledSpellListGrantsNothing() throws {
        let resolver = try ActorSpellFixture.resolver(
            npcs: [ActorSpellFixture.npc(formID: Form.wizard, spells: [Form.boltList])],
            leveledSpells: [ActorSpellFixture.lvsp(formID: Form.boltList, entries: [])]
        )

        #expect(resolver.baseline(for: FormID(Form.wizard)).actorSpells.isEmpty)
    }

    // MARK: - Degrading

    @Test func aBrokenTemplateChainResolvesToNothing() throws {
        let resolver = try ActorSpellFixture.resolver(npcs: [
            ActorSpellFixture.npc(
                formID: Form.wizard,
                templateFlags: 0x0008,
                template: 0x0000_0999,
                spells: [Form.firebolt]
            )
        ])

        #expect(resolver.baseline(for: FormID(Form.wizard)) == .none)
    }

    @Test func aSubjectWithNoRecordsBehindItKnowsNothing() throws {
        let resolver = try ActorSpellFixture.resolver(
            npcs: [ActorSpellFixture.npc(formID: Form.wizard, spells: [Form.firebolt])]
        )

        #expect(resolver.baseline(for: .player) == .none)
        #expect(resolver.baseline(for: .generated) == .none)
    }
}
