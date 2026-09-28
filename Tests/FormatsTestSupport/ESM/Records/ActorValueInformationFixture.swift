// Record builder shared by the parser tests and the runtime tests that feed
// the same records to a store. Every byte is built in code.

import Foundation
@testable import OpenSkyFormats

public enum ActorValueInformationFixture: Sendable {
    public static func skillUse(
        useMultiplier: Float = 1.5,
        useOffset: Float = 2.5,
        improveMultiplier: Float = 3.5,
        improveOffset: Float = 4.5
    ) -> Data {
        words([
            useMultiplier.bitPattern,
            useOffset.bitPattern,
            improveMultiplier.bitPattern,
            improveOffset.bitPattern
        ])
    }

    /// One perk-tree node in the field order the spec gives: PNAM, FNAM, XNAM,
    /// YNAM, HNAM, VNAM, SNAM, the CNAM connection run, then INAM.
    public static func node(
        perk: UInt32 = 0,
        parentRequired: UInt32 = 1,
        column: UInt32 = 0,
        row: UInt32 = 0,
        horizontal: Float = 0,
        vertical: Float = 0,
        skill: UInt32 = 0,
        connections: [UInt32] = [],
        index: UInt32 = 0
    ) -> Data {
        var data = ESMFixture.field("PNAM", words([perk]))
        data += ESMFixture.field("FNAM", words([parentRequired]))
        data += ESMFixture.field("XNAM", words([column]))
        data += ESMFixture.field("YNAM", words([row]))
        data += ESMFixture.field("HNAM", words([horizontal.bitPattern]))
        data += ESMFixture.field("VNAM", words([vertical.bitPattern]))
        data += ESMFixture.field("SNAM", words([skill]))
        for connection in connections {
            data += ESMFixture.field("CNAM", words([connection]))
        }
        data += ESMFixture.field("INAM", words([index]))
        return data
    }

    public static func record(type: String, formID: UInt32 = 0, fields: Data) throws -> ESMRecord {
        let file = try ESMFile(
            data: ESMFixture.tes4()
                + ESMFixture.topGroup(
                    type,
                    contents: ESMFixture.record(type, formID: formID, data: fields)
                )
        )
        guard let group = file.topGroups.first else {
            throw ESMError.malformed("fixture has no top group")
        }
        guard let child = try group.children().first else {
            throw ESMError.malformed("fixture group has no child")
        }
        guard case let .record(record) = child else {
            throw ESMError.malformed("fixture child is not a record")
        }
        return record
    }

    public static func words(_ values: [UInt32]) -> Data {
        var data = Data()
        for value in values {
            data.appendUInt32(value)
        }
        return data
    }
}
