// AIDT decode coverage (issue #503): the named values, the defensive length
// handling, and the `useAIData` template inheritance the hostility derivation
// depends on. No game-derived bytes.

import Foundation
@testable import opensky
import Testing

struct ActorAIDataTests {
    @Test
    func decodesEveryNamedValueAndTheAggroDistances() throws {
        let base = try actor(aiData: FactionFixture.aiData(
            aggression: 2,
            confidence: 4,
            energy: 75,
            morality: 3,
            mood: 5,
            assistance: 2,
            aggroRadiusBehavior: true,
            unknown: 0xAB,
            warn: 500,
            warnOrAttack: 750,
            attack: 1000
        ))
        let data = try #require(base.aiData)

        #expect(data.aggression == .veryAggressive)
        #expect(data.confidence == .foolhardy)
        #expect(data.energy == 75)
        #expect(data.morality == .noCrime)
        #expect(data.mood == 5)
        #expect(data.assistance == .helpsFriendsAndAllies)
        #expect(data.usesAggroRadiusBehavior)
        #expect(data.unknown == 0xAB)
        #expect(data.warnDistance == 500)
        #expect(data.warnOrAttackDistance == 750)
        #expect(data.attackDistance == 1000)
    }

    /// A value outside the named range is kept, not clamped: a mod may author
    /// one, and reading it as a real setting would be an invention.
    @Test
    func keepsValuesTheSpecDoesNotName() throws {
        let base = try actor(aiData: FactionFixture.aiData(
            aggression: 9, confidence: 9, morality: 9, assistance: 9
        ))
        let data = try #require(base.aiData)

        #expect(data.aggression == .unknown(raw: 9))
        #expect(data.confidence == .unknown(raw: 9))
        #expect(data.morality == .unknown(raw: 9))
        #expect(data.assistance == .unknown(raw: 9))
        #expect(data.aggression.rawValue == 9)
        #expect(data.aggression.description == "unknown (9)")
    }

    /// A record written before the aggro block keeps everything it did author.
    @Test
    func aShortStructKeepsWhatItAuthoredAndDropsTheDistances() throws {
        let base = try actor(aiData: FactionFixture.aiData(
            aggression: 1, byteCount: ActorAIData.requiredByteCount
        ))
        let data = try #require(base.aiData)

        #expect(data.aggression == .aggressive)
        #expect(data.warnDistance == nil)
        #expect(data.warnOrAttackDistance == nil)
        #expect(data.attackDistance == nil)
    }

    /// Too short to read at all, and a record with no AIDT: both leave the
    /// actor without AI data rather than failing the whole record.
    @Test
    func anUnreadableOrAbsentStructLeavesNoAIData() throws {
        #expect(try actor(aiData: FactionFixture.aiData(byteCount: 4)).aiData == nil)
        #expect(try actor(aiData: Data()).aiData == nil)
        // And the documented stand-in never starts a fight.
        #expect(ActorAIData.absent.aggression == .unaggressive)
    }

    /// The flag byte's other seven bits are not the aggro-radius bit.
    @Test
    func readsOnlyTheLowBitOfTheFlagByte() throws {
        var full = FactionFixture.aiData(aggroRadiusBehavior: true)
        var clear = FactionFixture.aiData(aggroRadiusBehavior: false)
        // Field payload starts after the 6-byte field header; offset 6 is the
        // flag byte.
        full[full.startIndex + 12] = 0xFF
        clear[clear.startIndex + 12] = 0xFE
        #expect(try actor(aiData: full).aiData?.usesAggroRadiusBehavior == true)
        #expect(try actor(aiData: clear).aiData?.usesAggroRadiusBehavior == false)
    }

    /// The AI data delegates on its own flag, independently of the SNAM run.
    @Test
    func aiDataInheritsThroughItsOwnTemplateFlag() throws {
        let template = try actor(
            formID: 0x600,
            editorID: "Template",
            aiData: FactionFixture.aiData(aggression: 3)
        )
        let inheriting = try actor(
            formID: 0x601,
            editorID: "Inheriting",
            templateFlags: 0x0010,
            template: 0x600,
            aiData: FactionFixture.aiData(aggression: 0)
        )
        let owning = try actor(
            formID: 0x602,
            editorID: "Owning",
            template: 0x600,
            aiData: FactionFixture.aiData(aggression: 0)
        )
        let resolver = ActorTemplateResolver(
            actors: Dictionary(uniqueKeysWithValues: [template, inheriting, owning].map {
                ($0.formID.rawValue, $0)
            }),
            leveledActors: [:]
        )

        let inherited = try resolver.resolveFactions(base: FormID(0x601))
        #expect(inherited.aiData.value?.aggression == .frenzied)
        #expect(inherited.aiData.source == FormID(0x600))

        let own = try resolver.resolveFactions(base: FormID(0x602))
        #expect(own.aiData.value?.aggression == .unaggressive)
        #expect(own.aiData.source == FormID(0x602))

        // And the baseline resolver hands the same answer to the runtime.
        let baselines = ActorFactionBaselineResolver(templates: resolver)
        #expect(baselines.baseline(for: FormID(0x601)).aiData.aggression == .frenzied)
        #expect(baselines.baseline(for: .player) == .none)
    }

    private func actor(
        formID: UInt32 = 0x600,
        editorID: String = "Actor",
        templateFlags: UInt16 = 0,
        template: UInt32? = nil,
        aiData: Data
    ) throws -> ActorBase {
        try ActorBase(
            record: FactionFixture.decode(FactionFixture.actor(
                formID: formID,
                editorID: editorID,
                templateFlags: templateFlags,
                template: template,
                aiData: aiData
            )),
            localized: false
        )
    }
}
