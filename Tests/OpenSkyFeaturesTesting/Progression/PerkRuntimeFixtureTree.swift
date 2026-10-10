// The AVIF perk tree the spend suites climb, and two spell-record helpers.
// Split from `PerkRuntimeFixture.swift` for the body-length cap.

import Foundation
@testable import OpenSkyFormatsTesting

@MainActor
extension PerkRuntimeFixture {
    /// The AVIF record with the fixture perk tree, shaped like the install's
    /// `AVOneHanded`: an empty entry node leads to the first box. Only a chain's
    /// head sits in a box, as in vanilla.
    public static var actorValueInformationRecord: Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("AVOneHanded"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("One-Handed"))
        fields += ESMFixture.field("CNAM", PerkFixture.word(1))
        fields += ESMFixture.field("AVSK", PerkFixture.floats([6.3, 0, 2, 0]))
        fields += treeNode(perk: 0, connections: [1], index: 0)
        fields += treeNode(perk: Perk.damageRank1, connections: [2, 3], index: 1)
        fields += treeNode(perk: Perk.blocking, connections: [], index: 2)
        fields += treeNode(perk: Perk.skillGated, connections: [], index: 3)
        return ESMFixture.record(
            "AVIF", formID: ActorValueInformation.oneHanded, data: fields
        )
    }

    /// One perk-tree node in the field order the spec gives: PNAM, FNAM, XNAM,
    /// YNAM, HNAM, VNAM, SNAM, the CNAM connection run, then INAM.
    private static func treeNode(
        perk: UInt32,
        connections: [UInt32],
        index: UInt32
    ) -> Data {
        var data = ESMFixture.field("PNAM", PerkFixture.word(perk))
        data += ESMFixture.field("FNAM", PerkFixture.word(1))
        data += ESMFixture.field("XNAM", PerkFixture.word(index))
        data += ESMFixture.field("YNAM", PerkFixture.word(0))
        data += ESMFixture.field("HNAM", PerkFixture.float(0))
        data += ESMFixture.field("VNAM", PerkFixture.float(0))
        data += ESMFixture.field("SNAM", PerkFixture.word(ActorValueInformation.oneHanded))
        for connection in connections {
            data += ESMFixture.field("CNAM", PerkFixture.word(connection))
        }
        return data + ESMFixture.field("INAM", PerkFixture.word(index))
    }

    /// One EFID/EFIT entry of a fixture spell. A named type rather than a tuple
    /// because three members is past the strict-lint tuple cap.
    public struct EffectSpec {
        public let effect: UInt32
        public let magnitude: Float
        public let duration: UInt32
    }

    /// A SPEL with an authored manual cost, an optional half-cost perk link and
    /// an optional effect list.
    public static func spellRecord(
        formID: UInt32,
        editorID: String,
        baseCost: UInt32,
        halfCostPerk: UInt32 = 0,
        effects: [EffectSpec] = []
    ) -> Data {
        var spit = Data()
        spit.appendUInt32(baseCost)
        // Bit 0 is "Manual Cost Calc", so the authored cost above is the one
        // the runtime charges and every assertion is arithmetic on one number.
        spit.appendUInt32(1)
        for _ in 0 ..< 6 {
            spit.appendUInt32(0)
        }
        spit.appendUInt32(halfCostPerk)
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        fields += ESMFixture.field("FULL", ESMFixture.zstring(editorID))
        fields += ESMFixture.field("SPIT", spit)
        for effect in effects {
            fields += InventoryFixture.effectFields(
                effect: effect.effect,
                magnitude: effect.magnitude,
                area: 0,
                duration: effect.duration
            )
        }
        return ESMFixture.record("SPEL", formID: formID, data: fields)
    }
}
