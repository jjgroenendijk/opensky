// The INFO VMAD fragment tail (issue #426), over synthetic bytes built from the
// UESP and xEdit layout in `DialogueFixture`.
//
// The layout's unusual property is that the fragment count is not stored: it is
// the population of the flag byte, and the entries arrive in bit order. Most of
// what is worth testing follows from that, which is why the cases below are
// about which flag bits are set rather than about string parsing.

import Foundation
@testable import opensky
import Testing

struct TopicInfoFragmentTests {
    private func info(_ tail: Data, scripts: [VMADFixture.Script] = []) throws -> TopicInfo {
        try DialogueFixture.info(
            DialogueFixture.infoData()
                + DialogueFixture.vmad(scripts: scripts, tail: tail)
        )
    }

    /// Both boxes: two entries, begin first, and both named against the same
    /// generated file the way the Creation Kit writes them.
    @Test func decodesBothResultBoxes() throws {
        let info = try info(DialogueFixture.infoFragmentTail(
            fileName: "TIF__00012345", begin: "Fragment_0", end: "Fragment_1"
        ))
        let section = try #require(info.script.infoFragments)
        #expect(section.extraBindDataVersion == 2)
        #expect(section.flags == 3)
        #expect(section.fileName == "TIF__00012345")
        #expect(info.fragments.map(\.phase) == [.begin, .end])
        #expect(section.fragment(.begin)?.functionName == "Fragment_0")
        #expect(section.fragment(.end)?.functionName == "Fragment_1")
        #expect(section.fragment(.end)?.scriptName == "TIF__00012345")
        #expect(info.fragmentScriptName == "TIF__00012345")
        #expect(info.script.skipped.total == 0)
    }

    /// One box only. The end fragment of a response with just a begin script is
    /// absent rather than the same entry read twice, which is the mistake a
    /// stored count would have hidden.
    @Test func decodesASingleResultBox() throws {
        let begin = try info(DialogueFixture.infoFragmentTail(
            fileName: "TIF__1", begin: "Fragment_0"
        ))
        #expect(begin.fragments.map(\.phase) == [.begin])
        #expect(begin.script.infoFragments?.fragment(.end) == nil)

        let end = try info(DialogueFixture.infoFragmentTail(
            fileName: "TIF__2", end: "Fragment_0"
        ))
        #expect(end.fragments.map(\.phase) == [.end])
        #expect(end.script.infoFragments?.fragment(.begin) == nil)
    }

    /// A tail declaring no fragment at all decodes to an empty section, and the
    /// response reports no result script rather than an empty name.
    @Test func aTailWithNoFlagsDecodesEmpty() throws {
        let info = try info(DialogueFixture.infoFragmentTail(fileName: "TIF__3"))
        #expect(info.script.infoFragments?.isEmpty == true)
        #expect(info.fragmentScriptName == nil)
    }

    /// The primary script list still reaches the runtime when a tail follows
    /// it, which is the whole reason the tail is read rather than skipped.
    @Test func primaryScriptsSurviveBesideTheTail() throws {
        let info = try info(
            DialogueFixture.infoFragmentTail(fileName: "TIF__4", begin: "Fragment_0"),
            scripts: [VMADFixture.Script("SomeInfoScript", properties: [])]
        )
        #expect(info.script.scripts.map(\.name) == ["SomeInfoScript"])
        #expect(info.fragments.count == 1)
    }

    /// A flag bit outside the two documented ones cannot be paired with an
    /// entry, so the tail is refused and tallied while the record survives —
    /// the mod-quirk rule, not a thrown decode.
    @Test func anUndocumentedFlagBitTalliesTheTail() throws {
        let info = try info(DialogueFixture.infoFragmentTail(
            fileName: "TIF__5", begin: "Fragment_0", flags: 0x05
        ))
        #expect(info.script.infoFragments == nil)
        #expect(info.fragments.isEmpty)
        #expect(info.script.skipped.ranked.contains { $0.name == "INFO fragments" })
    }

    /// A truncated tail is likewise tallied rather than thrown, and the record
    /// keeps everything decoded before it.
    @Test func aTruncatedTailTalliesTheTail() throws {
        var tail = DialogueFixture.infoFragmentTail(
            fileName: "TIF__6", begin: "Fragment_0"
        )
        tail = tail.dropLast(4)
        let info = try info(tail, scripts: [VMADFixture.Script("Kept", properties: [])])
        #expect(info.script.infoFragments == nil)
        #expect(info.script.scripts.map(\.name) == ["Kept"])
        #expect(info.script.skipped.ranked.contains { $0.name == "INFO fragments" })
    }
}
