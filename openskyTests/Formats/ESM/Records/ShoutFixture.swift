// Byte builders for the M19 shout-family suites (issue #467). Synthetic and
// assembled in code from the published record layouts — never extracted game
// files (AGENTS.md "Legal & IP boundary").
//
// Lives in openskyTests/ rather than openskyTestSupport/ because only the
// synthetic suites use it; the real-data sweep reads the user's install.

import Foundation
@testable import opensky
import Testing

enum ShoutFixture {
    /// One SNAM entry's authored values.
    struct WordSpec {
        let word: UInt32
        let spell: UInt32
        let recovery: Float

        init(word: UInt32, spell: UInt32, recovery: Float) {
            self.word = word
            self.spell = spell
            self.recovery = recovery
        }
    }

    /// One SHOU with a FULL, a DESC, an MDOB and one SNAM per requested word.
    static func shout(editorID: String, words: [WordSpec]) throws -> ESMRecord {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Fire Breath"))
        var menuObject = Data()
        menuObject.appendUInt32(0x0C01)
        fields += ESMFixture.field("MDOB", menuObject)
        fields += ESMFixture.field("DESC", ESMFixture.zstring("Your voice is fire."))
        for entry in words {
            fields += ESMFixture.field("SNAM", wordEntry(entry))
        }
        return try record(type: "SHOU", fields: fields)
    }

    /// A 12-byte SNAM: word FormID, spell FormID, recovery time.
    static func wordEntry(_ entry: WordSpec) -> Data {
        var data = Data()
        data.appendUInt32(entry.word)
        data.appendUInt32(entry.spell)
        data.appendFloat32(entry.recovery)
        return data
    }

    /// A 12-byte LVLO: uint16 level, two pad bytes, FormID, uint32 count.
    static func leveledEntry(level: UInt16, reference: UInt32, count: UInt32 = 1) -> Data {
        var data = Data()
        data.appendUInt16(level)
        data.appendUInt16(0)
        data.appendUInt32(reference)
        data.appendUInt32(count)
        return data
    }

    /// A single-record plugin parsed back into the one record it holds.
    static func record(type: String, fields: Data, formID: UInt32 = 0x123) throws -> ESMRecord {
        let plugin = ESMFixture.tes4()
            + ESMFixture.topGroup(
                type,
                contents: ESMFixture.record(type, formID: formID, data: fields)
            )
        let file = try ESMFile(data: plugin)
        let group = try #require(file.topGroups.first { $0.recordType?.description == type })
        let child = try #require(try group.children().first)
        guard case let .record(record) = child else {
            throw ESMError.malformed("fixture child is not a record")
        }
        return record
    }
}
