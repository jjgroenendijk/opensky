// A minimal REFR for the placed-reference field suites.

import Foundation
@testable import OpenSkyFormatsESM

public enum PlacedReferenceFixture: Sendable {
    /// The base every fixture reference places.
    public static let base: UInt32 = 0x0002_D4E2

    /// REFR 0x1000 with a NAME, a zeroed DATA, and `extraFields` after them.
    public static func reference(_ extraFields: Data) throws -> PlacedReference {
        var name = Data()
        name.appendUInt32(base)
        let fields = ESMFixture.field("NAME", name)
            + ESMFixture.field("DATA", Data(count: 24))
            + extraFields
        return try PlacedReference(
            record: ESMFixture.parseRecord(ESMFixture.record("REFR", formID: 0x1000, data: fields))
        )
    }
}
