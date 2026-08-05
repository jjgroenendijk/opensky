// The hash that links a NIF collision shape to a MATT record (issue #358).
//
// nif.xml documents `SkyrimHavokMaterial` as "CRC32 of the lowercase of the
// Creation Kit Material Name" without naming the CRC parameters, so the table
// below is the evidence for the ones `HavokMaterialHash` implements: each pair
// is a Creation Kit material name and the value nif.xml lists for it. No game
// bytes are involved — these are spec constants.

@testable import opensky
import Testing

struct HavokMaterialHashTests {
    /// Creation Kit material name -> the `SkyrimHavokMaterial` value nif.xml
    /// lists. Names with a space and names without one both appear because
    /// Bethesda's own material names are inconsistent about it, and the hash is
    /// over the string verbatim.
    static let nifXMLValues: [(name: String, value: UInt32)] = [
        ("Stone", 3_741_512_247),
        ("Snow", 398_949_039),
        ("Wood", 500_811_281),
        ("Gravel", 428_587_608),
        ("Grass", 1_848_600_814),
        ("Dirt", 3_106_094_762),
        ("Sand", 2_168_343_821),
        ("Ice", 873_356_572),
        ("Water", 1_024_582_599),
        ("Glass", 3_739_830_338),
        ("Cloth", 3_839_073_443),
        ("Skin", 591_247_106),
        ("Mud", 1_486_385_281),
        ("Organic", 2_974_920_155),
        ("Web", 3_934_839_107),
        ("Ward", 3_895_166_727),
        ("Dragon", 2_518_321_175),
        ("Bottle", 493_553_910),
        ("Barrel", 732_141_076),
        ("Broken Stone", 131_151_687),
        ("Light Wood", 365_420_259),
        ("Heavy Stone", 1_570_821_952),
        ("Heavy Metal", 2_229_413_539),
        ("Heavy Wood", 3_070_783_559),
        ("Solid Metal", 1_288_358_971),
        ("MaterialCarpet", 1_286_705_471),
        ("MaterialBlade1Hand", 1_060_167_844),
        ("MaterialWaterPuddle", 3_764_646_153),
        ("MaterialStoneAsStairs", 1_886_078_335),
        ("MaterialCarriageWheel", 322_207_473),
        ("StairsStone", 899_511_101),
        ("StairsBrokenStone", 2_892_392_795)
    ]

    @Test func hashesEveryDocumentedMaterialName() {
        for entry in Self.nifXMLValues {
            #expect(
                HavokMaterialHash.value(ofMaterialName: entry.name) == entry.value,
                "\(entry.name)"
            )
        }
    }

    @Test func caseDoesNotMatter() {
        #expect(
            HavokMaterialHash.value(ofMaterialName: "STONE")
                == HavokMaterialHash.value(ofMaterialName: "stone")
        )
    }

    /// The empty register is the documented value for "no material", so an
    /// unnamed material must not collide with a real one.
    @Test func theEmptyNameHashesToZero() {
        #expect(HavokMaterialHash.value(ofMaterialName: "") == 0)
    }
}
