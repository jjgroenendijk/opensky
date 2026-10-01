// Synthetic KYWD records and the small keyword and form-list plugins that the
// store suites and the record-dump suites share.

import Foundation
@testable import OpenSkyFormatsESM

public enum KeywordFixture: Sendable {
    /// A KYWD with an EDID, plus a CNAM colour when `hasColor` is set.
    public static func recordBytes(
        formID: UInt32,
        editorID: String,
        hasColor: Bool = false
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        if hasColor {
            fields += ESMFixture.field("CNAM", Data([1, 2, 3, 4]))
        }
        return ESMFixture.record("KYWD", formID: formID, data: fields)
    }

    /// A plugin with an FLST group and a KYWD group, each written only when it
    /// has records.
    public static func plugin(
        masters: [String] = [],
        formLists: [Data] = [],
        keywords: [Data] = []
    ) throws -> ESMFile {
        var data = ESMFixture.tes4(masters: masters)
        if !formLists.isEmpty {
            data += ESMFixture.topGroup("FLST", contents: formLists.reduce(Data(), +))
        }
        if !keywords.isEmpty {
            data += ESMFixture.topGroup("KYWD", contents: keywords.reduce(Data(), +))
        }
        return try ESMFile(data: data)
    }
}
