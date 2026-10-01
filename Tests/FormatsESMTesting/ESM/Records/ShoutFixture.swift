// Byte builders for the shout-family suites, built in code from the published
// record layouts.

import FormatsCoreTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import Testing

public enum ShoutFixture: Sendable {
    /// One SNAM entry's authored values.
    public struct WordSpec: Sendable {
        public let word: UInt32
        public let spell: UInt32
        public let recovery: Float

        public init(word: UInt32, spell: UInt32, recovery: Float) {
            self.word = word
            self.spell = spell
            self.recovery = recovery
        }
    }

    /// One SHOU with a FULL, a DESC, an MDOB and one SNAM per requested word.
    public static func shout(editorID: String, words: [WordSpec]) throws -> ESMRecord {
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
    public static func wordEntry(_ entry: WordSpec) -> Data {
        var data = Data()
        data.appendUInt32(entry.word)
        data.appendUInt32(entry.spell)
        data.appendFloat32(entry.recovery)
        return data
    }

    /// A 12-byte LVLO: uint16 level, two pad bytes, FormID, uint32 count.
    public static func leveledEntry(level: UInt16, reference: UInt32, count: UInt32 = 1) -> Data {
        var data = Data()
        data.appendUInt16(level)
        data.appendUInt16(0)
        data.appendUInt32(reference)
        data.appendUInt32(count)
        return data
    }

    /// A single-record plugin parsed back into the one record it holds.
    public static func record(
        type: String,
        fields: Data,
        formID: UInt32 = 0x123
    ) throws -> ESMRecord {
        try ESMFixture.parsedRecord(type: type, fields: fields, formID: formID)
    }
}
