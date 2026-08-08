// Env-gated NIF particle sweep over the user's own Skyrim SE install
// (read-only external input, never committed — AGENTS.md Legal & IP): resolves
// every model path referenced by the WhiterunWorld city cells plus the Tamriel
// Whiterun-exterior home cell, opens each NIF through the VFS, and runs the
// particleSystems() decode. Gate for milestone 7.3.1: the whole set decodes
// with no throws, particle-bearing NIFs exist, and their effect shaders
// resolve. Skips automatically when OPENSKY_DATA_ROOT is unset/unresolvable
// (CI has no game data). Summary printed + written to logs/.

import Foundation
@testable import opensky
import Testing

struct ParticleRealDataTests {
    /// Real data only when explicitly pointed at via the env var; the
    /// locator's Steam-default fallback is deliberately not consulted so
    /// machines without the override skip deterministically.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// WhiterunWorld's populated grid span is a handful of cells around the
    /// origin; the range is deliberately generous and misses throw
    /// cellNotFound, which the sweep skips.
    private static let whiterunGrid = (x: Int32(-6) ... 10, y: Int32(-8) ... 6)

    @Test(.enabled(if: Self.dataRoot != nil))
    func sweepsWhiterunReferencedNIFs() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let fileSystem = VirtualFileSystem(root: root)
        let paths = try referencedModelPaths(file: file)
        try #require(!paths.isEmpty, "no model paths resolved from Whiterun cells")

        var stats = SweepStats()
        var failures: [String] = []
        for path in paths.sorted() {
            guard let data = try? fileSystem.contents(forPath: path) else {
                stats.unreadable += 1
                continue
            }
            do {
                let systems = try NIFFile(data: data).particleSystems()
                stats.accumulate(path: path, systems: systems)
            } catch {
                failures.append("\(path): \(error)")
            }
        }

        #expect(failures.isEmpty, "particle decode failures:\n\(failures.joined(separator: "\n"))")
        #expect(stats.particleFiles > 0, "Whiterun sweep found no particle-bearing NIFs")
        #expect(stats.systems > 0)
        #expect(stats.emitters > 0, "particle systems decoded but no emitters resolved")
        #expect(stats.effectShaders > 0, "no particle system resolved a BSEffectShaderProperty")

        let unsupported = stats.unsupported.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }.joined(separator: " ")
        let summary = """
        [INFO] Whiterun NIF particle sweep: \(paths.count) models \
        (\(stats.unreadable) unreadable), \(stats.particleFiles) particle-bearing, \
        0 decode failures
        [INFO] systems: \(stats.systems), emitters: \(stats.emitters), \
        modifiers: \(stats.modifiers), effect shaders resolved: \(stats.effectShaders), \
        alpha properties: \(stats.alphaProperties)
        [INFO] unsupported modifier histogram (type:count): \(unsupported)
        """
        print(summary)
        try? summary.write(to: logURL, atomically: true, encoding: .utf8)
    }

    /// Union of model VFS keys over the WhiterunWorld grid span + the Tamriel
    /// Whiterun-exterior cell used by every prior render gate.
    private func referencedModelPaths(file: ESMFile) throws -> Set<String> {
        let catalog = ExteriorCellModelCatalog(file: file)
        var paths: Set<String> = []
        for gridX in Self.whiterunGrid.x {
            for gridY in Self.whiterunGrid.y {
                guard
                    let cellPaths = try? catalog.modelPaths(
                        worldspaceEditorID: "WhiterunWorld",
                        gridX: gridX,
                        gridY: gridY
                    ) else { continue }
                paths.formUnion(cellPaths)
            }
        }
        try paths.formUnion(catalog.modelPaths(
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
            gridX: FirstRenderCell.gridX,
            gridY: FirstRenderCell.gridY
        ))
        return paths
    }

    private struct SweepStats {
        var unreadable = 0
        var particleFiles = 0
        var systems = 0
        var emitters = 0
        var modifiers = 0
        var effectShaders = 0
        var alphaProperties = 0
        var unsupported: [String: Int] = [:]

        mutating func accumulate(path: String, systems decoded: [ParticleSystemDefinition]) {
            guard !decoded.isEmpty else { return }
            particleFiles += 1
            systems += decoded.count
            for system in decoded {
                emitters += system.emitters.count
                modifiers += system.modifiers.count
                effectShaders += system.effectShader == nil ? 0 : 1
                alphaProperties += system.alphaProperty == nil ? 0 : 1
                for modifier in system.modifiers {
                    if case let .unsupported(typeName) = modifier.kind {
                        unsupported[typeName, default: 0] += 1
                    }
                }
            }
        }
    }

    /// logs/particle-sweep.log (gitignored) next to the other real-data
    /// sidecars.
    private var logURL: URL {
        logsDirectory.appending(path: "particle-sweep.log")
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // openskyTests/
            .deletingLastPathComponent() // repo root
            .appending(path: "logs")
    }
}
