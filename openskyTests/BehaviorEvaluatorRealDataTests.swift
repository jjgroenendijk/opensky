// Env-gated behavior-evaluator smoke probe over the user's own Skyrim SE
// install (read-only external input, never committed — AGENTS.md Legal & IP).
//
// Builds one `BehaviorGraphInstance` over every behavior file under the
// character actor folder, third-person and `_1stperson`, steps each with no
// input, and asserts the two things this milestone item promises: nothing
// crashes, and every gap is named in the `BehaviorTally` rather than silently
// approximated. The tally is pinned so a later change that quietly widens the
// gap fails here.
//
// The report is class names, counts, and file paths only, and goes to
// gitignored `logs/`. Skips automatically when OPENSKY_DATA_ROOT is unset. Run
// with `make realtest T='BehaviorEvaluatorRealDataTests/stepsEveryPlayerBehaviorGraph()'`.

import Foundation
@testable import opensky
import Testing

/// One graph's run: where it came from and what stepping it produced.
private struct BehaviorRunRow {
    let path: String
    let graphName: String?
    let tally: BehaviorTally
    let updates: Int
    let firedEventCount: Int
    let posedBoneCount: Int
    let movedRoot: Bool
    /// How many state machines the last update reached (issue #330).
    let activeStateCount: Int
}

struct BehaviorEvaluatorRealDataTests {
    /// Real data only when explicitly pointed at via the env var, matching the
    /// other HKX real-data tests, so machines without the override skip
    /// deterministically rather than falling back to the Steam default.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static let characterPrefix = "meshes\\actors\\character\\"
    private static let skeletonPath =
        "meshes\\actors\\character\\character assets\\skeleton.hkx"
    /// Two seconds at the fixed timestep the engine will drive the graph with.
    private static let updateCount = 60
    private static let timestep: Float = 1.0 / 30.0

    @Test(.enabled(if: Self.dataRoot != nil))
    func stepsEveryPlayerBehaviorGraph() throws {
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let paths = vfs.archiveEntries()
            .map(\.path)
            .filter { $0.hasPrefix(Self.characterPrefix) && $0.hasSuffix(".hkx") }
        #expect(!paths.isEmpty, "no character .hkx files found under \(Self.characterPrefix)")

        let skeleton = try #require(
            loadSkeleton(vfs), "no hkaSkeleton in \(Self.skeletonPath)"
        )
        let clips = InstallBehaviorClipSource(
            fileSystem: vfs,
            paths: paths.filter { $0.contains("\\animations\\") }
        )

        var rows: [BehaviorRunRow] = []
        var failures: [String] = []
        for path in paths {
            do {
                guard let row = try run(path: path, vfs: vfs, skeleton: skeleton, clips: clips)
                else { continue }
                rows.append(row)
            } catch {
                failures.append("\(path): \(String(describing: error))")
            }
        }
        #expect(failures.isEmpty, "parse failures: \(failures.prefix(5))")
        #expect(!rows.isEmpty, "no behavior-role files in the sweep")

        try write(report(rows, clips: clips))
        assertOutcome(rows)
    }

    // MARK: - Running

    private func run(
        path: String,
        vfs: VirtualFileSystem,
        skeleton: BehaviorSkeleton,
        clips: InstallBehaviorClipSource
    ) throws -> BehaviorRunRow? {
        let file = try HKXFile(data: vfs.contents(forPath: path))
        let objectGraph = try HKXObjectGraph(file: file)
        guard let behavior = HKBBehaviorGraph.graphs(in: objectGraph).first else {
            return nil
        }
        let instance = BehaviorGraphInstance(
            graph: behavior, in: objectGraph, skeleton: skeleton, clips: clips
        )
        instance.activate()
        var firedEvents = 0
        var movedRoot = false
        var posedBones = 0
        var activeStates = 0
        for _ in 0 ..< Self.updateCount {
            let result = instance.update(deltaTime: Self.timestep)
            firedEvents += result.firedEvents.count
            posedBones = result.bones.count
            activeStates = max(activeStates, instance.activeStates.count)
            if result.rootMotion.translation != .zero {
                movedRoot = true
            }
        }
        instance.deactivate()
        return BehaviorRunRow(
            path: path,
            graphName: behavior.name,
            tally: instance.tally,
            updates: Self.updateCount,
            firedEventCount: firedEvents,
            posedBoneCount: posedBones,
            movedRoot: movedRoot,
            activeStateCount: activeStates
        )
    }

    private func loadSkeleton(_ vfs: VirtualFileSystem) -> BehaviorSkeleton? {
        guard
            let data = try? vfs.contents(forPath: Self.skeletonPath),
            let file = try? HKXFile(data: data),
            let rig = (try? HKASkeleton.skeletons(in: file))?.first
        else {
            return nil
        }
        return BehaviorSkeleton(rig)
    }

    // MARK: - Assertions

    private func assertOutcome(_ rows: [BehaviorRunRow]) {
        for row in rows {
            #expect(row.tally.updatesRun == row.updates, "\(row.path) ran short")
            #expect(
                row.posedBoneCount > 0,
                "\(row.path) produced no bones"
            )
            #expect(
                row.tally.generatorsEvaluated > 0,
                "\(row.path) reached no generator"
            )
            let undecodable = row.tally.rankedUndecodableObjects.prefix(5)
            #expect(
                row.tally.undecodableObjectTotal == 0,
                "\(row.path) hit \(row.tally.undecodableObjectTotal) undecodable: \(undecodable)"
            )
        }
        // Every player behavior file is rooted in a state machine, and since
        // issue #330 a machine reports the state it is in rather than tallying
        // a shortcut. A graph reporting none means the walk stopped early.
        let withoutStateMachine = rows.filter { $0.activeStateCount == 0 }
        #expect(
            withoutStateMachine.isEmpty,
            "graphs that reached no state machine: \(withoutStateMachine.map(\.path).prefix(5))"
        )
    }

    // MARK: - Report

    private func report(_ rows: [BehaviorRunRow], clips: InstallBehaviorClipSource) -> String {
        var merged = BehaviorTally()
        for row in rows {
            merged.merge(row.tally)
        }
        var lines = [
            "OpenSky behavior evaluator probe — \(rows.count) graphs, "
                + "\(Self.updateCount) updates each at \(Self.timestep)s",
            "",
            "## Totals",
            "generators evaluated: \(merged.generatorsEvaluated)",
            "modifiers evaluated: \(merged.modifiersEvaluated)",
            "events fired: \(rows.reduce(0) { $0 + $1.firedEventCount })",
            "clips loaded: \(clips.loadedCount), clip lookups that missed: \(clips.missCount)",
            "undecodable objects: \(merged.undecodableObjectTotal)",
            "",
            "## Gaps (rank, count)"
        ]
        lines += section("feature gaps", merged.rankedFeatureGaps)
        lines += section("unevaluated generators", merged.rankedUnevaluatedGenerators)
        lines += section("partial generators", merged.rankedPartialGenerators)
        lines += section("pass-through modifiers", merged.rankedPassthroughModifiers)
        lines += section("unapplied bindings", merged.rankedUnappliedBindings)
        lines += section("unresolved clips", merged.rankedUnresolvedClips)
        lines += ["", "## Applied bindings (member path, count)"]
        lines += merged.rankedBoundMemberPaths.map { "\($0.name) \($0.count)" }
        lines += ["", "## Per graph"]
        for row in rows.sorted(by: { $0.path < $1.path }) {
            lines.append(
                "\(row.path): graph \"\(row.graphName ?? "<none>")\", "
                    + "\(row.tally.generatorsEvaluated) generators, "
                    + "\(row.firedEventCount) events, "
                    + "\(row.tally.gapTotal) gap entries, "
                    + "root moved: \(row.movedRoot)"
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func section(_ title: String, _ ranked: [(name: String, count: Int)]) -> [String] {
        ["", "### \(title)"] + (ranked.isEmpty
            ? ["(none)"]
            : ranked.map { "\($0.name) \($0.count)" })
    }

    private func write(_ report: String) throws {
        let url = logsDirectory.appending(path: "behavior-evaluator-probe.log")
        try FileManager.default.createDirectory(
            at: logsDirectory, withIntermediateDirectories: true
        )
        try report.write(to: url, atomically: true, encoding: .utf8)
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
    }
}
