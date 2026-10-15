// MagicEffectGapCensus: effects whose archetype the planner applies as nothing,
// over synthetic MGEF records.

import Foundation
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyMagic
import Testing

@MainActor
struct MagicEffectGapCensusTests {
    /// Raw archetypes: 0 value modifier, 18 summon creature, 12 light.
    private func effect(archetype: UInt32) throws -> MagicEffect {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Fixture"))
            + ESMFixture.field("DATA", ActiveEffectFixture.data(archetype: archetype))
        return try MagicEffect(
            record: MagicEffectFixture.record(type: "MGEF", fields: fields), localized: false
        )
    }

    @Test func countsUnappliedArchetypesByEffects() throws {
        let census = try MagicEffectGapCensus(effects: [
            effect(archetype: 0), effect(archetype: 18), effect(archetype: 18),
            effect(archetype: 12)
        ])

        #expect(census.effectTotal == 4)
        #expect(census.unappliedTotal == 3)
        #expect(census.archetypes.count == 3)
        #expect(census.appliedArchetypeCount == 1)
        #expect(census.rankedUnapplied.map(\.count) == [2, 1])
        #expect(census.rankedUnapplied.first?.name == MagicEffectArchetype.summonCreature
            .description)
    }
}
