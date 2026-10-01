// Synthetic LCTN records for the location store and the location conditions.

import Foundation

public enum LocationFixture: Sendable {
    /// An LCTN with an EDID, an optional PNAM parent, and optional keywords.
    public static func recordBytes(
        _ formID: UInt32,
        _ editorID: String,
        parent: UInt32? = nil,
        keywords: [UInt32] = []
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        if let parent {
            fields += ESMFixture.field("PNAM", ESMFixture.words([parent]))
        }
        if !keywords.isEmpty {
            fields += ESMFixture.field("KSIZ", ESMFixture.words([UInt32(keywords.count)]))
                + ESMFixture.field("KWDA", ESMFixture.words(keywords))
        }
        return ESMFixture.record("LCTN", formID: formID, data: fields)
    }
}
