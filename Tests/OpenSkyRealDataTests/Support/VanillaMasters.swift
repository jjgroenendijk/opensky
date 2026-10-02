// The five masters every vanilla Skyrim SE install carries, in load order. The
// M22 record counts are measured over these files, not over the active load order.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData

enum VanillaMasters {
    static let names = [
        "Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm", "Dragonborn.esm"
    ]

    static func load(root: GameDataRoot) throws -> [(name: String, file: ESMFile)] {
        try names.map { name in
            try (name, ESMFile(url: root.dataURL.appending(path: name)))
        }
    }

    struct LiveRecord {
        let record: ESMRecord
        let localized: Bool
    }

    /// Every live record of `type` in each master, overrides included.
    static func liveRecords(
        of type: FourCC,
        in plugins: [(name: String, file: ESMFile)]
    ) -> [LiveRecord] {
        var skipped = SkippedRecords()
        return plugins.flatMap { plugin in
            let localized = plugin.file.isLocalized
            return plugin.file.liveRecords(of: type, skipped: &skipped).map {
                LiveRecord(record: $0, localized: localized)
            }
        }
    }
}
