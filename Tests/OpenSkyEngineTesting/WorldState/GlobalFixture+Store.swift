// The global store over synthetic GLOB records.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyWorldState

extension GlobalFixture {
    /// Store over `records` with no masters, so every GLOB resolves to
    /// `ReferenceKey.plugin(name: "test.esm", objectID:)`.
    public static func store(_ records: Data) throws -> GlobalStore {
        try GlobalStore(file: ESMFile(data: plugin(records)), pluginName: "Test.esm")
    }

    /// The key a fixture FormID resolves to under `store(_:)`.
    public static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "test.esm", objectID: objectID)
    }
}
