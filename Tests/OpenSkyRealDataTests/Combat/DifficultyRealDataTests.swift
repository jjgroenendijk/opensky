// Difficulty on the real install: the damage ratio for each level, from the
// load order's fDiffMult GMSTs or the UESP fallback. The report in `.logs/`
// holds the six levels, their multipliers, and where each value came from.

import Foundation
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyPhysics
import Testing

struct DifficultyRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot)) @MainActor
    func damageRatioFallsAsDifficultyRises() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let settings = DifficultySettings.resolve(
            store: GameSettingLoader.load(root: root, baseFile: file)
        )
        let levels = DifficultyLevel.allCases.map { settings.multipliers($0) }
        let ratios = levels.map { $0.damageByPlayer.value / $0.damageToPlayer.value }
        #expect(settings.multipliers(.adept).damageByPlayer.value == 1)
        #expect(settings.multipliers(.adept).damageToPlayer.value == 1)
        #expect(zip(ratios, ratios.dropFirst()).allSatisfy { $0 > $1 })

        let lines = zip(DifficultyLevel.allCases, levels).map { level, row in
            "\(level) byPlayer=\(row.damageByPlayer.value) (\(row.damageByPlayer.source)) "
                + "toPlayer=\(row.damageToPlayer.value) (\(row.damageToPlayer.source)) "
                + "xp=\(row.experience.value) (\(row.experience.source))"
        }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let directory = try RepositoryLogs.createdDirectory("difficulty-ratio/\(stamp)")
        try lines.joined(separator: "\n")
            .write(to: directory.appending(path: "ratio.txt"), atomically: true, encoding: .utf8)
    }
}
