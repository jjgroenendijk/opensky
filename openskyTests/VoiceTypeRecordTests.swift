// VTYP decoder tests over synthetic bytes. Layout: UESP VTYP and xEdit
// dev-4.1.6 `wbRecord(VTYP, ...)`.

import Foundation
@testable import opensky
import Testing

struct VoiceTypeRecordTests {
    @Test func decodesDirectoryNameAndFlags() throws {
        let voice = try DialogueFixture.voice(
            DialogueFixture.editorID("FemaleNord")
                + ESMFixture.field("DNAM", Data([0x03]))
        )
        #expect(voice.editorID == "FemaleNord")
        #expect(voice.flags == [.allowsDefaultDialogue, .female])
        #expect(voice.skipped.isEmpty)
    }

    @Test func malformedFlagTalliesAndKeepsEditorID() throws {
        let voice = try DialogueFixture.voice(
            ESMFixture.field("DNAM", Data())
                + DialogueFixture.editorID("UsableVoice")
        )
        #expect(voice.editorID == "UsableVoice")
        #expect(voice.skipped.counts[.malformedField("DNAM")] == 1)
    }
}
