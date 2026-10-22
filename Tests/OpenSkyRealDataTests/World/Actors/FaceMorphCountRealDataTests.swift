// Checks the morph count settings against the chargen TRI of each playable race and
// sex's default face. Writes every difference to .logs/face-morph-counts/.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyGameData
import Testing

struct FaceMorphCountRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func noChargenTRIHoldsMoreTypesThanTheSettingsAllow() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let fileSystem = VirtualFileSystem(root: root)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let store = GameSettingStore(plugins: [("Skyrim.esm", file)])
        let counts = FaceMorphCounts.resolve(store: store)
        var races: [Race] = []
        var headParts: [UInt32: HeadPart] = [:]
        ESMWalk.forEachRecord(in: file) { record in
            if
                record.type == "RACE", let race = try? Race(record: record, localized: true),
                race.flags.contains(.playable)
            {
                races.append(race)
            } else if
                record.type == "HDPT",
                let part = try? HeadPart(record: record, localized: true)
            {
                headParts[part.formID.rawValue] = part
            }
            return true
        }
        var lines = ["settings: nose \(counts.nose), brow \(counts.brow), "
            + "eye \(counts.eye), lip \(counts.lip)"]
        var tooMany: [String] = []
        for race in races {
            for (sex, parts) in [("male", race.maleHeadParts), ("female", race.femaleHeadParts)] {
                let name = "\(race.editorID ?? "?") \(sex)"
                let face = parts.compactMap { headParts[$0.rawValue] }
                    .first { $0.partType == .face }
                guard let path = face?.morphPaths.first(where: { $0.kind == .chargen })?.path
                else {
                    lines.append("\(name): no chargen TRI")
                    continue
                }
                let tri = try TRIFile(data: fileSystem.contents(forPath: "meshes\\" + path))
                let names = tri.morphTargets.map(\.name)
                lines += counts.mismatches(targetNames: names).map { "\(name) \(path): \($0)" }
                for group in FaceMorphCounts.groups {
                    let held = FaceMorphCounts.highestType(group.targetPrefix, in: names) + 1
                    if held > counts.count(partIndex: group.partIndex) ?? held {
                        tooMany.append("\(name): \(group.setting) below TRI's \(held)")
                    }
                }
            }
        }
        let dir = try RepositoryLogs.createdDirectory("face-morph-counts")
        try lines.joined(separator: "\n").write(
            to: dir.appending(path: "counts.txt"), atomically: true, encoding: .utf8
        )
        #expect(!races.isEmpty)
        #expect(tooMany.isEmpty, "see \(dir.path)/counts.txt")
    }
}
