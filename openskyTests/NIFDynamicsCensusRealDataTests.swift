// Env-gated Havok dynamics census over the user's own Skyrim SE install
// (read-only external input, never committed — AGENTS.md Legal & IP). Three
// sweeps: the models a representative block of Whiterun-area exterior cells
// places, the clutter meshes that carry the movable bodies, and every actor
// skeleton, which is where the ragdoll constraints live.
//
// The census fixes the motion-system list item 15.2 must support and the
// constraint list item 15.6 must instantiate — real-data decisions rather than
// what nif.xml says is representable. The report is counts, names, and paths
// only and goes to gitignored `logs/`; nothing extracted from the install
// enters the repository.
//
// Skips automatically when OPENSKY_DATA_ROOT is unset or unresolvable. Run with
// `make realtest T='NIFDynamicsCensusRealDataTests/censusesHavokDynamics()'`.

import Foundation
@testable import opensky
import Testing

struct NIFDynamicsCensusRealDataTests {
    /// Real data only when explicitly pointed at via the env var; the
    /// locator's Steam-default fallback is deliberately not consulted so
    /// machines without the override skip deterministically.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// A three-by-two block of Tamriel around the first render cell. Enough
    /// distinct statics to characterise world geometry without turning the
    /// census into a whole-worldspace sweep.
    private static let cells: [(x: Int32, y: Int32)] = [
        (6, -2), (5, -2), (7, -2), (6, -1), (5, -1), (7, -1)
    ]

    /// Movable props live under this prefix. Swept whole rather than sampled,
    /// because the point of the census is the tail of the mass distribution.
    private static let clutterPrefix = "meshes\\clutter\\"

    @Test(.enabled(if: Self.dataRoot != nil))
    func censusesHavokDynamics() throws {
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let esm = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))

        let world = try census(of: exteriorPaths(esm: esm), in: vfs)
        let clutter = census(of: clutterPaths(vfs), in: vfs)
        let skeletons = census(of: skeletonPaths(vfs), in: vfs)

        try write(report(world: world, clutter: clutter, skeletons: skeletons))
        assertWorld(world)
        assertClutter(clutter)
        assertSkeletons(skeletons)
    }

    // MARK: - Path discovery

    private func exteriorPaths(esm: ESMFile) throws -> [String] {
        let catalog = ExteriorCellModelCatalog(file: esm)
        var paths: Set<String> = []
        for cell in Self.cells {
            let cellPaths = try catalog.modelPaths(
                worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
                gridX: cell.x,
                gridY: cell.y
            )
            paths.formUnion(cellPaths)
        }
        return paths.sorted()
    }

    private func clutterPaths(_ vfs: VirtualFileSystem) -> [String] {
        vfs.archiveEntries()
            .map(\.path)
            .filter { $0.hasPrefix(Self.clutterPrefix) && $0.hasSuffix(".nif") }
            .sorted()
    }

    /// Every actor skeleton in the install, character and creature alike. The
    /// file name rather than one hardcoded path, because the creature
    /// skeletons are what make the constraint census more than one sample.
    private func skeletonPaths(_ vfs: VirtualFileSystem) -> [String] {
        vfs.archiveEntries()
            .map(\.path)
            .filter {
                $0.hasPrefix("meshes\\actors\\")
                    && $0.hasSuffix(".nif")
                    && ($0.contains("skeleton") || $0.contains("ragdoll"))
            }
            .sorted()
    }

    // MARK: - Sweep

    private func census(of paths: [String], in vfs: VirtualFileSystem) -> NIFDynamicsCensus {
        var census = NIFDynamicsCensus()
        for path in paths {
            do {
                let file = try NIFFile(data: vfs.contents(forPath: path))
                census.record(model: file.collisionModel(), path: path)
            } catch {
                census.record(loadFailure: String(describing: error), path: path)
            }
        }
        return census
    }

    // MARK: - Assertions

    private func assertWorld(_ census: NIFDynamicsCensus) {
        #expect(census.modelCount > 0, "no exterior models resolved")
        #expect(census.loadFailures.isEmpty, "load failures: \(census.loadFailures.prefix(5))")
        #expect(census.decodeFailureCount == 0)
        #expect(census.unsupportedBlocks.isEmpty, "unsupported: \(census.unsupportedBlocks)")
        #expect(!census.motionSystemCounts.isEmpty)
    }

    /// Clutter is the half of the install that is actually dynamic, so this is
    /// where the mass distribution has to come from. A zero here would mean the
    /// inertial tail is being read at the wrong offset.
    private func assertClutter(_ census: NIFDynamicsCensus) {
        #expect(census.modelCount > 0, "no clutter meshes found under \(Self.clutterPrefix)")
        #expect(census.loadFailures.isEmpty, "load failures: \(census.loadFailures.prefix(5))")
        #expect(census.simulatedBodyCount > 0, "no simulated bodies in clutter")
        #expect(census.mass.bodyCount > 0, "no clutter body carries a mass")
        #expect(census.mass.minimum > 0)
        #expect(census.mass.maximum < 100_000, "implausible mass \(census.mass.maximum) kg")
    }

    /// The ragdoll acceptance: the skeletons decode, they carry joints, and the
    /// joints name bones on both ends. Item 15.6 keys on exactly that.
    private func assertSkeletons(_ census: NIFDynamicsCensus) {
        #expect(census.modelCount > 0, "no actor skeletons found")
        #expect(census.loadFailures.isEmpty, "load failures: \(census.loadFailures.prefix(5))")
        #expect(!census.constraintTypeCounts.isEmpty, "no constraints on any skeleton")
        #expect(
            census.bonePairs.keys.contains { $0.bodyA != "<unbound>" && $0.bodyB != "<unbound>" },
            "no joint names a bone on both ends"
        )
        #expect(
            census.carrierCounts["bhkBlendCollisionObject", default: 0] > 0,
            "no skeleton body hangs off a bhkBlendCollisionObject"
        )
    }

    // MARK: - Report

    private func report(
        world: NIFDynamicsCensus,
        clutter: NIFDynamicsCensus,
        skeletons: NIFDynamicsCensus
    ) -> String {
        var lines = ["OpenSky Havok dynamics census", ""]
        lines += section("Exterior cell models", world)
        lines += section("Clutter meshes", clutter)
        lines += section("Actor skeletons", skeletons)
        lines += bonePairReport(skeletons)
        return lines.joined(separator: "\n") + "\n"
    }

    private func section(_ title: String, _ census: NIFDynamicsCensus) -> [String] {
        var lines = ["## \(title)"]
        lines.append("models: \(census.modelCount), "
            + "collision-bearing: \(census.collisionBearingModelCount), "
            + "bodies: \(census.bodyCount)")
        lines.append("simulated bodies: \(census.simulatedBodyCount), "
            + "zero mass: \(census.zeroMassBodyCount), "
            + "massless dynamic: \(census.masslessSimulatedBodyCount)")
        lines += histogram("motion systems", census.motionSystemCounts) {
            NIFMotionSystem(rawValue: $0).map { "\($0)" } ?? "unknown \($0)"
        }
        lines += histogram("quality types", census.qualityCounts) {
            NIFCollisionQuality(rawValue: $0).map { "\($0)" } ?? "unknown \($0)"
        }
        lines += histogram("layers", census.layerCounts) { "layer \($0)" }
        lines += named("carriers", census.carrierCounts)
        lines += massReport(census.mass)
        lines += named("constraint types", census.constraintTypeCounts)
        lines.append("unbound constraint ends: \(census.unboundConstraintEndCount)")
        lines += named("unsupported blocks", census.unsupportedBlocks)
        lines.append("decode failures: \(census.decodeFailureCount)")
        lines += list("decode failure detail", census.decodeFailures)
        lines += list("load failures", census.loadFailures)
        lines.append("")
        return lines
    }

    private func massReport(_ mass: NIFMassDistribution) -> [String] {
        guard let mean = mass.mean else { return ["mass: no body carries one"] }
        var lines = [String(
            format: "mass (kg): %d bodies, min %.3f, max %.3f, mean %.3f",
            mass.bodyCount, mass.minimum, mass.maximum, mean
        )]
        lines += mass.decades.sorted { $0.key < $1.key }.map { decade, count in
            "  1e\(decade) to 1e\(decade + 1): \(count)"
        }
        return lines
    }

    /// Every distinct joint-to-bone-pair binding, which is the list item 15.6
    /// instantiates against the animation skeleton.
    private func bonePairReport(_ census: NIFDynamicsCensus) -> [String] {
        let pairs = census.bonePairs
            .map { "\($0.key.type): \($0.key.bodyA) -> \($0.key.bodyB) (\($0.value))" }
            .sorted()
        return ["## Skeleton bone pairs (\(pairs.count) distinct)"] + pairs.map { "  \($0)" }
    }

    private func histogram(
        _ label: String,
        _ counts: [UInt8: Int],
        name: (UInt8) -> String
    ) -> [String] {
        guard !counts.isEmpty else { return [] }
        // Commonest first, ties broken by raw value so the report diffs
        // cleanly between runs.
        let ordered = counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
        return ["\(label):"] + ordered.map { "  \(name($0.key)) \($0.value)" }
    }

    private func named(_ label: String, _ counts: [String: Int]) -> [String] {
        guard !counts.isEmpty else { return [] }
        return ["\(label):"] + counts.sorted { $0.key < $1.key }.map { "  \($0.key) \($0.value)" }
    }

    private func list(_ label: String, _ values: [String]) -> [String] {
        guard !values.isEmpty else { return [] }
        return ["\(label): \(values.count)"] + values.prefix(50).map { "  \($0)" }
    }

    private func write(_ report: String) throws {
        let url = logsDirectory.appending(path: "nif-dynamics-census.log")
        try FileManager.default.createDirectory(
            at: logsDirectory, withIntermediateDirectories: true
        )
        try report.write(to: url, atomically: true, encoding: .utf8)
        print("[INFO] dynamics census: \(url.path)")
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
    }
}
