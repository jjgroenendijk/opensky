// The music the game plays for one moment, named by the default objects (`DOBJ`):
// combat, death, success, level up, and a cleared dungeon. See docs/engine/music.md.

import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public enum SpecialMusic: String, CaseIterable, Sendable {
    case battle = "BTMS"
    case death = "DTMS"
    case success = "SCMS"
    case levelUp = "LUMS"
    case dungeonCleared = "DCMS"

    /// Each special music type, merged by tag over every plugin's `DOBJ`, the last wins.
    static func types(
        in loadOrder: LoadOrderPlugins, skipped: inout SkippedRecords
    ) -> [SpecialMusic: FormID] {
        let versions = loadOrder.decodeEveryVersion(of: "DOBJ", skipped: &skipped) {
            try DefaultObjects(record: $0)
        }
        var result: [SpecialMusic: FormID] = [:]
        for key in versions.keys.sorted() {
            for version in versions[key] ?? [] {
                for kind in allCases {
                    guard let entry = version.entry(tag: kind.rawValue) else { continue }
                    result[kind] = entry.object
                }
            }
        }
        return result
    }
}
