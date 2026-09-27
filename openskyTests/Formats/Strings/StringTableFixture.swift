// Synthetic string table builder shared by StringTable tests. Fixtures are
// built in code — never extracted game files (AGENTS.md "Legal & IP boundary").
// Layout follows UESP "Skyrim Mod:String Table File Format";
// see docs/formats/strings.md.

import Foundation
@testable import opensky

enum StringTableFixture {
    /// Builds a whole table file: header, directory (in entry order), data
    /// block. `bytes` are raw string payloads, terminator added here.
    static func table(kind: StringTable.Kind, rawEntries: [(id: UInt32, bytes: Data)]) -> Data {
        var directory = Data()
        var block = Data()
        for entry in rawEntries {
            directory.appendUInt32(entry.id)
            directory.appendUInt32(UInt32(block.count))
            if kind.isLengthPrefixed {
                block.appendUInt32(UInt32(entry.bytes.count + 1))
            }
            block.append(entry.bytes)
            block.append(0)
        }
        var out = Data()
        out.appendUInt32(UInt32(rawEntries.count))
        out.appendUInt32(UInt32(block.count))
        out.append(directory)
        out.append(block)
        return out
    }

    static func table(kind: StringTable.Kind, entries: [(id: UInt32, text: String)]) -> Data {
        table(kind: kind, rawEntries: entries.map { ($0.id, Data($0.text.utf8)) })
    }
}
