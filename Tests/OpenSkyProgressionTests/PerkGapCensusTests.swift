// PerkGapCensus: entry points no engine code reads, and functions the evaluator
// does not compute, counted over synthetic PERK records.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyProgression
@testable import OpenSkyProgressionInterface
import Testing

struct PerkGapCensusTests {
    /// `Mod Buy Prices`, which no engine code reads.
    private static let modBuyPrices: UInt8 = 8
    /// Function raw values: 1 Set Value, 9 Add Activate Choice.
    private static let setValue: UInt8 = 1
    private static let addActivateChoice: UInt8 = 9

    private func perk(_ effects: [Data]) throws -> Perk {
        let fields = PerkFixture.fields(editorID: "Fixture", effects: effects)
        return try Perk(record: PerkFixture.record(fields: fields), localized: false)
    }

    @Test func ranksUnreadEntryPointsAndUnsupportedFunctions() throws {
        let read = PerkEntryPoint.modAttackDamage.rawValue
        let perks = try [
            perk([
                PerkFixture.entryPointEffect(entryPoint: read, function: Self.setValue),
                PerkFixture.entryPointEffect(entryPoint: Self.modBuyPrices, function: Self.setValue)
            ]),
            perk([
                PerkFixture.entryPointEffect(
                    entryPoint: Self.modBuyPrices, function: Self.addActivateChoice
                ),
                PerkFixture.abilityEffect(spell: 0x100)
            ])
        ]
        let census = PerkGapCensus(perks: perks)

        #expect(census.effectTotal == 3)
        #expect(census.entryPoints.count == 2)
        #expect(census.unreadEntryPoints.map(\.count) == [2])
        #expect(census.unreadEntryPoints.first?.name.hasPrefix("Mod Buy Prices") == true)
        #expect(census.unsupportedFunctions.map(\.count) == [1])
        #expect(census.unsupportedFunctions.first?.name == PerkFunction.addActivateChoice
            .description)
    }

    @Test func evaluatorSupportMatchesItsFunctionTable() {
        #expect(PerkEntryPointEvaluator.supports(.setValue))
        #expect(PerkEntryPointEvaluator.supports(.multiplyActorValueMultiplier))
        #expect(!PerkEntryPointEvaluator.supports(.addActivateChoice))
        #expect(!PerkEntryPointEvaluator.supports(.unknown(raw: 99)))
    }

    @Test func engineReadListsEveryNamedEntryPoint() {
        #expect(PerkEntryPoint.engineRead.count == 11)
        let unnamed = PerkEntryPoint.engineRead.filter { !$0.isKnown }
        #expect(unnamed.isEmpty)
    }
}
