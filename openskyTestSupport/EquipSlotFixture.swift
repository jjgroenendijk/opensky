// EQUP byte builder (issue #467), shared by the synthetic equipment suites and
// by `InventoryBaselineFixture`, whose weapons resolve their hands through an
// EQUP graph. Assembled in code from the published record layout — never
// extracted game files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky

enum EquipSlotFixture {
    /// One EQUP's fields: an editor ID, an optional packed PNAM parent array,
    /// and the uint32 DATA "use all parents" boolean.
    static func fields(
        editorID: String,
        parents: [UInt32],
        usesAllParents: Bool
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        if !parents.isEmpty {
            var packed = Data()
            for parent in parents {
                packed.appendUInt32(parent)
            }
            fields += ESMFixture.field("PNAM", packed)
        }
        var data = Data()
        data.appendUInt32(usesAllParents ? 1 : 0)
        fields += ESMFixture.field("DATA", data)
        return fields
    }

    static func record(
        formID: UInt32,
        editorID: String,
        parents: [UInt32] = [],
        usesAllParents: Bool = false
    ) -> Data {
        ESMFixture.record(
            "EQUP",
            formID: formID,
            data: fields(
                editorID: editorID,
                parents: parents,
                usesAllParents: usesAllParents
            )
        )
    }
}
