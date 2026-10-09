// Env-gated head-part sweep over every NPC_ of Skyrim.esm. Each NPC resolves
// without a throw, each resolved part names a mesh that exists, and the
// parts-per-head histogram goes to .logs/head-part-assembly/.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct HeadPartAssemblyRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func everyNPCResolvesItsHeadParts() throws {
        let install = try RealDataInstall.load()
        let resolvers = install.sceneBuilder().actorResolversBuildingIfNeeded()
        var npcs: [FormID] = []
        ESMWalk.forEachRecord(in: install.file) { record in
            if record.type == "NPC_" {
                npcs.append(FormID(record.formID))
            }
            return true
        }
        var failures: [String] = []
        var histogram: [Int: Int] = [:]
        var misses: [String: Int] = [:]
        var missingMeshes: Set<String> = []
        for npc in npcs {
            do {
                let visual = try resolvers.visual.resolve(
                    appearance: resolvers.template.resolve(base: npc)
                )
                histogram[visual.headParts.parts.count, default: 0] += 1
                for miss in visual.headParts.misses {
                    misses[HeadAssemblyReadout.missText(miss.reason), default: 0] += 1
                }
                missingMeshes.formUnion(visual.headParts.parts.map(\.modelPath).filter {
                    !install.fileSystem.exists("meshes\\" + $0)
                })
            } catch {
                failures.append("\(npc): \(error)")
            }
        }
        let report = ["NPCs: \(npcs.count), failed: \(failures.count)"]
            + histogram.sorted { $0.key < $1.key }.map { "\($0.key) parts: \($0.value) NPCs" }
            + misses.sorted { $0.key < $1.key }.map { "miss \($0.key): \($0.value)" }
            + ["missing meshes: \(missingMeshes.sorted())"] + failures.prefix(50)
        try report.joined(separator: "\n").write(
            to: RepositoryLogs.createdDirectory("head-part-assembly").appending(path: "sweep.log"),
            atomically: true, encoding: .utf8
        )
        let assembled = histogram.filter { $0.key > 0 }.values.reduce(0, +)
        #expect(npcs.count > 2000)
        #expect(assembled > npcs.count / 2, "\(histogram)")
        #expect(missingMeshes.isEmpty)
        #expect(failures.count < npcs.count / 100, "\(failures.prefix(5))")
    }
}
