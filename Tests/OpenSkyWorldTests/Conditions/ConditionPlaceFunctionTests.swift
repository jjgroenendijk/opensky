// The place condition functions: deaths per base, location ref types alive, the
// player's regions, and map markers. A missing seam fails with a reason.

import Foundation
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkyWorld
import Testing

struct ConditionPlaceFunctionTests {
    private static let subject = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.subjectFormID)
    private static let plugin = "Test.esm"
    private static let town: UInt32 = 0x0500
    private static let bossType: UInt32 = 0x0600

    private static func key(_ objectID: UInt32) -> ReferenceKey {
        ReferenceKey(resolved: ResolvedFormID(plugin: plugin, objectID: objectID))
    }

    /// One town listing two references of the boss ref type.
    private static func locations() throws -> LocationStore {
        let town = ESMFixture.record(
            "LCTN", formID: town,
            data: ESMFixture.field("EDID", ESMFixture.zstring("Town"))
                + ESMFixture.field("LCSR", ESMFixture.words([bossType, 0x700, 0x3C, 0]))
                + ESMFixture.field("LCSR", ESMFixture.words([bossType, 0x701, 0x3C, 0]))
        )
        return try LocationStore(plugins: [(plugin, ESMFile(
            data: ESMFixture.tes4() + ESMFixture.topGroup("LCTN", contents: town)
        ))])
    }

    private static func evaluate(
        _ function: UInt16, equals value: Float,
        parameter1: UInt32 = 0, parameter2: UInt32 = 0,
        places: PlaceConditionResolution = PlaceConditionResolution(deadReferences: [])
    ) throws -> ConditionOutcome {
        var context = try ConditionEvaluatorFixture.populatedContext()
        let townID = ResolvedFormID(plugin: plugin, objectID: town)
        context.data = try ConditionDataResolution(
            locations: locations(), sourcePlugin: plugin,
            currentLocations: [subject: townID, .player: townID]
        )
        context.places = places
        var evaluator = ConditionEvaluator(context: context)
        return try evaluator.evaluate(ConditionEvaluatorFixture.condition(
            comparisonValue: value.bitPattern, functionIndex: function,
            parameter1: parameter1, parameter2: parameter2
        ))
    }

    @Test func refTypesCountTheLivingOnly() throws {
        #expect(try Self.evaluate(563, equals: 1, parameter1: Self.bossType) == .true)
        #expect(try Self
            .evaluate(592, equals: 2, parameter1: Self.town, parameter2: Self.bossType) == .true)
        let oneDead = PlaceConditionResolution(deadReferences: [Self.key(0x700)])
        #expect(try Self.evaluate(
            592, equals: 1, parameter1: Self.town, parameter2: Self.bossType, places: oneDead
        ) == .true)
    }

    @Test func deadCountReadsTheBase() throws {
        let deaths = PlaceConditionResolution(deadReferences: [], deadCounts: [FormID(0x900): 3])
        #expect(try Self.evaluate(84, equals: 3, parameter1: 0x900, places: deaths) == .true)
        #expect(try Self.evaluate(84, equals: 0, parameter1: 0x901, places: deaths) == .true)
        #expect(try Self.evaluate(84, equals: 0, parameter1: 0x900, places: .empty).failures
            == [.unavailableActorState])
    }

    @Test func regionsAndLoadedLocation() throws {
        let inRegion = PlaceConditionResolution(playerRegions: [FormID(0x800)])
        #expect(try Self.evaluate(117, equals: 1, parameter1: 0x800, places: inRegion) == .true)
        #expect(try Self.evaluate(117, equals: 0, parameter1: 0x801, places: inRegion) == .true)
        #expect(try Self.evaluate(625, equals: 1, parameter1: Self.town) == .true)
    }

    @Test func markerVisibilityReadsTheRunOn() throws {
        let shown = PlaceConditionResolution(visibleMarkers: [Self.subject])
        #expect(try Self.evaluate(491, equals: 1, places: shown) == .true)
        #expect(try Self.evaluate(
            491,
            equals: 0,
            places: PlaceConditionResolution(visibleMarkers: [])
        ) == .true)
    }
}
