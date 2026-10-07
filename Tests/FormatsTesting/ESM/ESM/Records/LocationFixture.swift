// Synthetic LCTN records for the location store and the location conditions.

import Foundation

public enum LocationFixture: Sendable {
    /// An LCTN with an EDID, an optional PNAM parent, optional keywords, and
    /// optional `LCUN` triples of actor base, reference, and location.
    public static func recordBytes(
        _ formID: UInt32,
        _ editorID: String,
        parent: UInt32? = nil,
        keywords: [UInt32] = [],
        uniqueActors: [UInt32] = []
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        if let parent {
            fields += ESMFixture.field("PNAM", ESMFixture.words([parent]))
        }
        if !keywords.isEmpty {
            fields += ESMFixture.field("KSIZ", ESMFixture.words([UInt32(keywords.count)]))
                + ESMFixture.field("KWDA", ESMFixture.words(keywords))
        }
        if !uniqueActors.isEmpty {
            fields += ESMFixture.field("LCUN", ESMFixture.words(uniqueActors))
        }
        return ESMFixture.record("LCTN", formID: formID, data: fields)
    }
}
