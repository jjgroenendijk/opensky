// The AVIF perk tree the spend suites climb (issue #499, roadmap item 20.6),
// plus the two spell-record helpers that go with it.
//
// Split out of `PerkRuntimeFixture.swift` because that type is at the
// strict-lint body-length cap: what stays there is the record *lists* a suite
// reads, and what moved here is the byte-level authoring under them.
//
// Every byte is authored here; nothing comes from the game install (AGENTS.md
// "Legal & IP boundary"). The shape is this machine's `AVOneHanded`, read
// 2026-08-20 with `openskycli record AVOneHanded`.

import Foundation
@testable import opensky

@MainActor
extension PerkRuntimeFixture {
    /// The AVIF record carrying the fixture perk tree.
    ///
    /// Shaped like this machine's `AVOneHanded`, read 2026-08-20: an entry node
    /// granting no perk whose line reaches the first real box, that box's lines
    /// reaching two more, and every higher rank of a chain absent from the tree
    /// because vanilla puts only the chain head in a box.
    ///
    ///     #0 NULL          -> [1]
    ///     #1 DamageRank1   -> [2, 3]
    ///     #2 ShieldWall    -> []
    ///     #3 SkillGated    -> []
    static var actorValueInformationRecord: Data {
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
    struct EffectSpec {
        let effect: UInt32
        let magnitude: Float
        let duration: UInt32
    }

    /// A SPEL with an authored manual cost, an optional half-cost perk link and
    /// an optional effect list.
    static func spellRecord(
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
