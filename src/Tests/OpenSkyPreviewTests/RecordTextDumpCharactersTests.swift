// The character record views in the Asset Browser: an `IDLM` and an `HDPT`
// summary, and the body-part node table and tagfile bone binding.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyPreview
import Testing

struct RecordTextDumpCharactersTests {
    private typealias Fixture = ESMFixture

    @Test func dumpsAnIdleMarker() throws {
        let dump = try RecordTextDump.dump(record: Fixture.record("IDLM", fields: [
            ("EDID", Fixture.zstring("LeanMarker")),
            ("IDLF", Fixture.u8(0x01)),
            ("IDLT", Fixture.f32(5)),
            ("IDLA", Fixture.u32(0x800, 0x801))
        ]), localized: false)
        #expect(dump.contains("decoded IDLM: editorID LeanMarker, idles 2, flags 1, timer 5.0"))
    }

    @Test func dumpsAHeadPart() throws {
        let dump = try RecordTextDump.dump(record: Fixture.record("HDPT", fields: [
            ("EDID", Fixture.zstring("HairMale1")),
            ("PNAM", Fixture.u32(3)),
            ("CNAM", Fixture.u32(0x900))
        ]), localized: false)
        #expect(dump.contains("decoded HDPT: editorID HairMale1, type hair, model -"))
        #expect(dump.contains("color 00000900"))
    }

    @Test func bodyPartNodesReportWhichNodesTheSkeletonHas() {
        let parts = [(part: "Head", node: "NPC Head [Head]"), (part: "Tail", node: "Tail01")]
        #expect(AssetInfoText.bodyPartNodes(parts, skeleton: ["NPC Head [Head]"]) == """
        Nodes: 1 of 2 found in the skeleton
        Head: NPC Head [Head] · found
        Tail: Tail01 · missing
        """)
        #expect(AssetInfoText.bodyPartNodes(parts, skeleton: nil).hasPrefix(
            "Nodes: skeleton not loaded"
        ))
    }

    @Test func tagfileBonesBindToTheSkeleton() {
        #expect(AssetInfoText.boneBinding(["A", "B"], skeleton: ["A"])
            == "Bones: 1 of 2 bind to the skeleton\nMissing: B")
        #expect(AssetInfoText
            .boneBinding(["A"], skeleton: ["A"]) == "Bones: 1 of 1 bind to the skeleton")
        #expect(AssetInfoText.boneBinding([], skeleton: nil) == "Bones: none")
    }
}
