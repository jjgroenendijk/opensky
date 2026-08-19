// Synthetic PERK decode coverage: one case per effect type, the condition-tab
// grouping, the EPFD unions, and the malformed shapes a mod can author.
// Fixtures are built in code and contain no bytes from the game install.

import Foundation
@testable import opensky
import Testing

struct PerkRecordTests {
    @Test
    func decodesIdentityHeaderConditionsAndNextPerkLink() throws {
        let fields = PerkFixture.fields(
            editorID: "AlchemySkillBoosts",
            name: "Physician",
            description: "Potions you mix are more powerful.",
            conditions: [DialogueFixture.condition(functionIndex: 448, comparisonValue: 1)],
            header: PerkFixture.header(level: 20, rankCount: 3),
            nextPerk: 0x51,
            effects: [PerkFixture.entryPointEffect(
                entryPoint: 66,
                function: 2,
                tabs: [(runOn: 0, conditions: [])],
                functionType: 1,
                functionData: PerkFixture.float(1.25)
            )]
        )

        let perk = try Perk(
            record: PerkFixture.record(formID: 0x50, fields: fields),
            localized: false
        )

        #expect(perk.formID == FormID(0x50))
        #expect(perk.editorID == "AlchemySkillBoosts")
        #expect(perk.name == .inline("Physician"))
        #expect(perk.description == .inline("Potions you mix are more powerful."))
        #expect(perk.nextPerk == FormID(0x51))
        #expect(perk.conditions.conditions.count == 1)
        #expect(perk.skipped.total == 0)

        let data = try #require(perk.data)
        #expect(data.level == 20)
        #expect(data.rankCount == 3)
        #expect(data.isPlayable)
        #expect(!data.isTrait)
        #expect(!data.isHidden)
        #expect(perk.declaredRankCount == 3)
    }

    @Test
    func decodesQuestAbilityAndEntryPointEffects() throws {
        let fields = PerkFixture.fields(
            editorID: "MixedPerk",
            effects: [
                PerkFixture.questEffect(quest: 0x1234, stage: 40),
                PerkFixture.abilityEffect(spell: 0x2345),
                PerkFixture.entryPointEffect(
                    entryPoint: 51, // Apply Combat Hit Spell
                    function: 10, // Select Spell
                    tabs: [
                        (runOn: 0, conditions: [DialogueFixture.condition(functionIndex: 448)]),
                        (runOn: 2, conditions: [])
                    ],
                    functionType: 5,
                    functionData: PerkFixture.word(0x3456)
                )
            ]
        )

        let perk = try Perk(
            record: PerkFixture.record(formID: 0x60, fields: fields),
            localized: false
        )

        #expect(perk.skipped.total == 0)
        #expect(perk.effects.count == 3)
        // Bound outside the macro: `allSatisfy` is `rethrows`, and the
        // expansion does not mark the call `try`.
        let terminated = perk.effects.allSatisfy(\.isTerminated)
        #expect(terminated)

        #expect(perk.effects[0].type == .quest)
        #expect(perk.effects[0].data == .quest(quest: FormID(0x1234), stage: 40))

        #expect(perk.effects[1].type == .ability)
        #expect(perk.effects[1].data == .ability(spell: FormID(0x2345)))
        #expect(perk.effects[1].spell == FormID(0x2345))

        let entry = perk.effects[2]
        #expect(entry.type == .entryPoint)
        #expect(entry.entryPoint == PerkEntryPoint(rawValue: 51))
        #expect(entry.entryPoint?.name == "Apply Combat Hit Spell")
        #expect(entry.data == .entryPoint(PerkEntryPointEffect(
            entryPoint: PerkEntryPoint(rawValue: 51),
            function: .selectSpell,
            conditionTabCount: 2
        )))
        #expect(entry.functionType == .spell)
        #expect(entry.functionData == .spell(FormID(0x3456)))
        #expect(entry.spell == FormID(0x3456))
        #expect(perk.entryPointEffects.count == 1)
    }

    /// Each PRKC opens a tab and every CTDA after it belongs to that tab, which
    /// is the only thing that separates two condition runs inside one effect.
    @Test
    func groupsConditionsUnderTheTabThatOpenedThem() throws {
        let fields = PerkFixture.fields(
            editorID: "TabbedPerk",
            effects: [PerkFixture.entryPointEffect(
                entryPoint: 0,
                function: 3,
                tabs: [
                    (runOn: 0, conditions: [
                        DialogueFixture.condition(functionIndex: 448, comparisonValue: 1),
                        DialogueFixture.condition(functionIndex: 449, comparisonValue: 2)
                    ]),
                    (runOn: 1, conditions: [
                        DialogueFixture.condition(functionIndex: 450, comparisonValue: 3)
                    ]),
                    (runOn: 2, conditions: [])
                ],
                functionType: 1,
                functionData: PerkFixture.float(2)
            )]
        )

        let perk = try Perk(
            record: PerkFixture.record(fields: fields),
            localized: false
        )
        let effect = try #require(perk.effects.first)

        #expect(perk.skipped.total == 0)
        #expect(effect.conditionTabs.map(\.runOn) == [0, 1, 2])
        #expect(effect.conditionTabs.map(\.conditions.conditions.count) == [2, 1, 0])
        #expect(effect.conditionTabs[0].conditions.conditions.map(\.functionIndex) == [448, 449])
        #expect(effect.conditionTabs[1].conditions.conditions.map(\.functionIndex) == [450])
        // The record's own condition run stays empty: every CTDA here arrived
        // after a PRKE and belongs to a tab.
        #expect(perk.conditions.isEmpty)
    }

    /// EPFT 2 reads as an actor value and a factor under the four actor-value
    /// functions, and as a plain float pair under every other one
    /// (`wbEPFDDecider`).
    @Test
    func readsTheFloatPairPayloadThroughTheDeclaredFunction() throws {
        let pair = try decodeFunctionData(
            function: 4, // Add Range To Value
            functionType: 2,
            payload: PerkFixture.floats([1.5, 4.5])
        )
        #expect(pair == .floatPair(1.5, 4.5))

        let actorValue = try decodeFunctionData(
            function: 13, // Multiply Actor Value Mult
            functionType: 2,
            payload: PerkFixture.actorValueMultiplier(actorValue: 6, factor: 0.5)
        )
        #expect(actorValue == .actorValueMultiplier(actorValue: 6, factor: 0.5))
    }

    @Test
    func readsEveryDeclaredFunctionDataShape() throws {
        let value = try decodeFunctionData(
            function: 1,
            functionType: 1,
            payload: PerkFixture.float(3.5)
        )
        #expect(value == .float(3.5))
        let leveledItem = try decodeFunctionData(
            function: 8,
            functionType: 3,
            payload: PerkFixture.word(0x99)
        )
        #expect(leveledItem == .leveledItem(FormID(0x99)))
        let text = try decodeFunctionData(
            function: 11,
            functionType: 6,
            payload: ESMFixture.zstring("fSomeGameSetting")
        )
        #expect(text == .text("fSomeGameSetting"))
        let localized = try decodeFunctionData(
            function: 15,
            functionType: 7,
            payload: ESMFixture.zstring("Read")
        )
        #expect(localized == .localizedText(.inline("Read")))
    }

    /// Function 9 is the one shape that uses all four subrecords: the spell in
    /// EPFD, the button label in EPF2, and the flag pair in EPF3.
    @Test
    func decodesTheActivateChoiceLabelAndScriptFlags() throws {
        let fields = PerkFixture.fields(
            editorID: "ActivateChoicePerk",
            effects: [PerkFixture.entryPointEffect(
                entryPoint: 14, // Activate
                function: 9, // Add Activate Choice
                tabs: [(runOn: 0, conditions: [])],
                functionType: 4,
                functionData: PerkFixture.word(0x77),
                buttonLabel: "Harvest",
                scriptFlags: (options: 0x0002, fragmentIndex: 3)
            )]
        )

        let perk = try Perk(record: PerkFixture.record(fields: fields), localized: false)
        let effect = try #require(perk.effects.first)

        #expect(perk.skipped.total == 0)
        #expect(effect.functionType == .spellWithLabelAndFlags)
        #expect(effect.functionData == .spell(FormID(0x77)))
        #expect(effect.buttonLabel == .inline("Harvest"))
        let flags = try #require(effect.scriptFlags)
        #expect(flags.options == .replaceDefault)
        #expect(!flags.options.contains(.runImmediately))
        #expect(flags.fragmentIndex == 3)
    }

    /// Builds a one-effect perk around one EPFD payload and hands back what it
    /// decoded to, which is what every function-data case here is checking.
    private func decodeFunctionData(
        function: UInt8,
        functionType: UInt8,
        payload: Data
    ) throws -> PerkFunctionData? {
        let fields = PerkFixture.fields(
            editorID: "FunctionDataPerk",
            effects: [PerkFixture.entryPointEffect(
                entryPoint: 0,
                function: function,
                tabs: [(runOn: 0, conditions: [])],
                functionType: functionType,
                functionData: payload
            )]
        )
        let perk = try Perk(record: PerkFixture.record(fields: fields), localized: false)
        #expect(perk.skipped.total == 0)
        return perk.effects.first?.functionData
    }
}
