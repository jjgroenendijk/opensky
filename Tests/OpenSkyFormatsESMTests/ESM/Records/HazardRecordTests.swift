// HAZD, PHZD and PGRE, and the XLOC / XESP / XMRK extras of REFR, over
// synthetic fields. Layout sources: xEdit wbDefinitionsTES5.pas; see
// docs/formats/hazards.md and docs/formats/placed-references.md.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct HazardRecordTests {
    private typealias Fixture = ESMFixture

    private static let hazardData = Fixture.u32(5) + Fixture.f32(128, 30, 256, 0.5)
        + Fixture.u32(0x05) + Fixture.u32(0x100, 0, 0x200, 0x300)

    @Test func decodesHazard() throws {
        let hazard = try Hazard(record: Fixture.record("HAZD", fields: [
            ("EDID", Fixture.zstring("FireHazard")),
            ("MODL", Fixture.zstring("fx\\fire.nif")),
            ("MNAM", Fixture.u32(0x400)),
            ("DATA", Self.hazardData)
        ]), localized: false)
        #expect(hazard.editorID == "FireHazard")
        #expect(hazard.model?.path == "fx\\fire.nif")
        #expect(hazard.imageSpaceModifier == FormID(0x400))
        let properties = try #require(hazard.properties)
        #expect(properties.limit == 5)
        #expect(properties.radius == 128)
        #expect(properties.affectsPlayerOnly)
        #expect(properties.alignsToImpactNormal)
        #expect(!properties.dropsToGround)
        #expect(properties.spell == FormID(0x100))
        #expect(properties.light == nil)
        #expect(properties.sound == FormID(0x300))
        #expect(hazard.skipped.isEmpty)
    }

    @Test func truncatedDataIsTalliedAndUnknownFieldIsCounted() throws {
        let hazard = try Hazard(record: Fixture.record("HAZD", fields: [
            ("DATA", Self.hazardData.prefix(12)),
            ("ZZZZ", Fixture.u8(1))
        ]), localized: false)
        #expect(hazard.properties == nil)
        #expect(hazard.skipped.counts[.malformedField("DATA")] == 1)
        #expect(hazard.skipped.counts[.unknownField("ZZZZ")] == 1)
    }

    @Test func wrongRecordTypeThrows() {
        #expect(throws: ESMError.self) {
            _ = try Hazard(record: Fixture.record("HAZE", fields: []), localized: false)
        }
    }

    @Test func decodesPlacedHazardAndProjectile() throws {
        let fields: [(String, Data)] = [
            ("NAME", Fixture.u32(0x900)),
            ("XESP", Fixture.u32(0x901) + Fixture.u8(1, 0, 0, 0)),
            ("XEZN", Fixture.u32(0x902)),
            ("DATA", Fixture.f32(1, 2, 3, 0, 0, 1.5))
        ]
        let hazard = try PlacedProjectile(record: Fixture.record("PHZD", fields: fields))
        #expect(hazard.base == FormID(0x900))
        #expect(hazard.enableParent?.parent == FormID(0x901))
        #expect(hazard.enableParent?.isOppositeOfParent == true)
        #expect(hazard.encounterZone == FormID(0x902))
        #expect(hazard.placement.position == SIMD3(1, 2, 3))
        #expect(hazard.scale == 1)
        #expect(hazard.skipped.isEmpty)
        let projectile = try PlacedProjectile(record: Fixture.record("PGRE", fields: fields))
        #expect(projectile.recordType == "PGRE")
    }

    @Test func decodesLockEnableParentAndMapMarkerOnReference() throws {
        let reference = try PlacedReference(record: Fixture.record("REFR", fields: [
            ("NAME", Fixture.u32(0x10)),
            (
                "XLOC",
                Fixture.u8(50, 0, 0, 0) + Fixture.u32(0x77) + Fixture.u8(0x04, 0, 0, 0)
                    + Fixture.u32(0, 0)
            ),
            ("XESP", Fixture.u32(0x55) + Fixture.u8(2, 0, 0, 0)),
            ("XMRK", Data()),
            ("FNAM", Fixture.u8(0x03)),
            ("FULL", Fixture.zstring("Whiterun")),
            ("TNAM", Fixture.u8(2, 0)),
            ("DATA", Fixture.f32(0, 0, 0, 0, 0, 0))
        ]))
        #expect(reference.lock?.level == .adept)
        #expect(reference.lock?.key == FormID(0x77))
        #expect(reference.lock?.isLeveled == true)
        #expect(reference.lock?.size == 20)
        #expect(reference.enableParent?.popsIn == true)
        #expect(reference.mapMarker?.isVisible == true)
        #expect(reference.mapMarker?.canTravelTo == true)
        #expect(reference.mapMarker?.type?.rawValue == 2)
        #expect(reference.mapMarker?.name(localized: false) == LString.inline("Whiterun"))
        #expect(reference.skipped.isEmpty)
    }

    @Test func unknownLockLevelIsKept() {
        #expect(LockLevel(rawValue: 7) == .unknown(7))
        #expect(LockLevel(rawValue: 255) == .requiresKey)
    }
}
