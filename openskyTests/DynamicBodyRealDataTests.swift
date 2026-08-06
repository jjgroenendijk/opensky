// Env-gated dynamic-body probe over the user's own Skyrim SE install
// (read-only external input, never committed — AGENTS.md "Legal & IP"),
// issue #193, roadmap item 15.2.
//
// The synthetic suites prove the solver against boxes and a floor. The claims
// they cannot make are the ones that decide whether this feature works at all:
// that a vanilla clutter-heavy interior actually produces simulated bodies from
// its own Havok data, that those bodies settle rather than sink or explode,
// that a shove moves them, and that stepping them costs a frame budget the
// renderer can afford. All four come from the install or the whole thing is a
// well-tested no-op.
//
// The report is counts and timings only and goes to gitignored `logs/`;
// nothing extracted from the install enters the repository.
//
// Skips automatically when OPENSKY_DATA_ROOT is unset. Run with
// `make realtest T='DynamicBodyRealDataTests/settlesAndPushesVanillaClutter()'`,
// or `make realtest-perf` to hold the step to the budget an optimized build is
// held to rather than the unoptimized ceiling.

import Foundation
import Metal
@testable import opensky
import simd
import Testing

struct DynamicBodyRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static let device = MTLCreateSystemDefaultDevice()

    private static var canRun: Bool {
        dataRoot != nil && (device?.supportsFamily(.metal4) ?? false)
    }

    /// The perf budget for one physics step, in milliseconds: a 1/120 step has
    /// 8.33 ms of wall clock and the solver must not become the frame's critical
    /// path. Measured 0.37 ms average over this cell when this landed, so the
    /// budget carries the margin `docs/testing.md` asks a perf gate to carry.
    ///
    /// It applies to an *optimized* build, which is the one that ships. A step
    /// is a few hundred microseconds of `simd` arithmetic in tight loops, and
    /// that is exactly the code Swift's `-Onone` treats worst: the same run
    /// measures around twenty-four times slower unoptimized, so holding a plain
    /// `make realtest` to 2 ms would be measuring the compiler rather than the
    /// engine. `make realtest-perf` builds this suite with `-O` and the gate
    /// below is the real one; a default `make realtest` still gates, at the
    /// unoptimized ceiling, so a regression cannot hide there either.
    private static let stepBudgetMS = 2.0

    /// The same gate for an unoptimized build: the measured 8.9 ms with room for
    /// the noise a Debug run carries. Loose on purpose — it exists to catch a
    /// regression of the *kind* this issue fixed, not to certify performance.
    private static let unoptimizedStepBudgetMS = 20.0

    /// Whichever of the two the running build is held to.
    private static var budgetMS: Double {
        #if OPENSKY_OPTIMIZED
            stepBudgetMS
        #else
            unoptimizedStepBudgetMS
        #endif
    }

    /// How far below its start pose a settled body may end up, in engine units.
    /// The farmhouse's rooms are under 200 units tall, so anything past this is
    /// a body that left the geometry it was authored in rather than one that
    /// fell onto the floor beneath it.
    private static let maximumSettledDropUnits: Float = 512

    /// How long the probe simulates, in fixed steps. Five seconds of world
    /// time, which is past the point vanilla clutter stops moving.
    private static let settleSteps = 600

    /// How many settled bodies the shove phase walks into, in key order.
    private static let shovedBodyCount = 8

    @Test(.enabled(if: Self.canRun))
    func settlesAndPushesVanillaClutter() throws {
        let root = try #require(Self.dataRoot)
        let device = try #require(Self.device)
        let fileSystem = VirtualFileSystem(root: root)
        let textures = TextureLibrary(fileSystem: fileSystem, device: device)
        let builder = try CellSceneBuilder(
            file: ESMFile(url: root.dataURL.appending(path: "Skyrim.esm")),
            meshes: MeshLibrary(fileSystem: fileSystem, device: device, textures: textures),
            textures: textures,
            fileSystem: fileSystem
        )
        builder.simulatesDynamicBodies = true
        let scene = try builder.buildInteriorScene(cellFormID: WalkPathRoute.farmInterior)

        let placements = scene.dynamicBodies
        #expect(!placements.isEmpty, "the vanilla farmhouse placed no simulated body")
        var world = DynamicBodyWorld()
        world.setCell(.interior(WalkPathRoute.farmInterior), placements: placements)
        let start = world.bodies.map { (key: $0.key, position: $0.position) }

        let settle = try Self.settle(world: &world, scene: scene)
        let shove = Self.shove(world: &world, scene: scene)

        try Self.write(report: Self.report(
            scene: scene, start: start, settle: settle, shove: shove, world: world
        ))

        #expect(settle.nonFiniteCount == 0, "a body integrated to a non-finite pose")
        #expect(settle.recoveredBodyCount == 0, "a body had to be reset mid-step")
        // Every reference the cell simulates comes to rest inside five seconds
        // of world time, and comes to rest near where it was authored rather
        // than at the bottom of the world. Those two together are item 15.2's
        // settle criterion (issue #392): before it was met, half this cell's
        // clutter left the geometry it started in and fell tens of thousands of
        // units, while the rest sat still without ever sleeping, so neither a
        // count of sleepers alone nor a finite-pose check alone would have
        // caught it.
        #expect(
            settle.sleepingCount == world.bodyCount,
            "\(world.bodyCount - settle.sleepingCount) of \(world.bodyCount) never came to rest"
        )
        #expect(
            settle.maximumDrop < Self.maximumSettledDropUnits,
            "a body fell \(settle.maximumDrop) units out of the geometry it was authored in"
        )
        #expect(shove.movedBodyCount > 0, "a shove moved nothing")
        #expect(
            settle.averageStepMS <= Self.budgetMS,
            "physics step averaged \(settle.averageStepMS) ms against a \(Self.budgetMS) ms budget"
        )
    }

    // MARK: - Phases

    private struct SettleResult {
        var averageStepMS = 0.0
        var maximumStepMS = 0.0
        var sleepingCount = 0
        var nonFiniteCount = 0
        var recoveredBodyCount = 0
        var maximumDrop: Float = 0
        var settledTransformCount = 0
    }

    private struct ShoveResult {
        var movedBodyCount = 0
        var wokenBodyCount = 0
    }

    private static func settle(
        world: inout DynamicBodyWorld,
        scene: CellScene
    ) throws -> SettleResult {
        let starts = Dictionary(
            world.bodies.map { ($0.key, $0.position) }, uniquingKeysWith: { first, _ in first }
        )
        let step = DynamicStepWorld(staticCandidates: { bounds in
            scene.staticCollision.candidates(overlapping: bounds)
        })
        var result = SettleResult()
        var totalNanoseconds: UInt64 = 0
        for _ in 0 ..< settleSteps {
            let began = DispatchTime.now().uptimeNanoseconds
            world.advance(by: WalkController.fixedTimeStep, world: step)
            let elapsed = DispatchTime.now().uptimeNanoseconds - began
            totalNanoseconds += elapsed
            result.maximumStepMS = max(result.maximumStepMS, Double(elapsed) / 1_000_000)
            result.recoveredBodyCount += world.lastStats.recoveredBodyCount
            result.settledTransformCount += world.drainSettledTransforms().count
        }
        result.averageStepMS = Double(totalNanoseconds) / 1_000_000 / Double(settleSteps)
        result.sleepingCount = world.sleepingBodyCount
        for body in world.bodies {
            if !body.position.isFiniteVector || !body.orientation.vector.isFiniteVector4 {
                result.nonFiniteCount += 1
                continue
            }
            guard let origin = starts[body.key] else { continue }
            result.maximumDrop = max(result.maximumDrop, origin.z - body.position.z)
        }
        return result
    }

    /// Walks a capsule into settled clutter and counts what moved.
    ///
    /// The capsule is placed just outside each of the first `shovedBodyCount`
    /// bodies in key order and walked into it, rather than at the average of
    /// every body's position. The average is where this probe used to stand, and
    /// it only ever worked because half the clutter was falling through the
    /// world at the time: now that every reference settles where it was
    /// authored, the centroid of a farmhouse's clutter is a point in mid-air in
    /// the middle of a room and a capsule there touches nothing. Key order keeps
    /// the choice deterministic and independent of which house this is.
    private static func shove(world: inout DynamicBodyWorld, scene: CellScene) -> ShoveResult {
        guard !world.bodies.isEmpty else { return ShoveResult() }
        let before = Dictionary(
            world.bodies.map { ($0.key, $0.position) }, uniquingKeysWith: { first, _ in first }
        )
        let capsule = PlayerCapsule.standard
        let walk = SIMD3<Float>(320, 0, 0)
        for body in world.bodies.prefix(shovedBodyCount) {
            let reach = capsule.radius + body.definition.boundingRadius - 1
            let feet = SIMD3(
                body.position.x - reach,
                body.position.y,
                body.position.z - capsule.height / 2
            )
            world.push(capsule: capsule, feetPosition: feet, velocity: walk)
        }
        var result = ShoveResult()
        result.wokenBodyCount = world.bodies.count(where: { !$0.isSleeping })
        let step = DynamicStepWorld(staticCandidates: { bounds in
            scene.staticCollision.candidates(overlapping: bounds)
        })
        for _ in 0 ..< 120 {
            world.advance(by: WalkController.fixedTimeStep, world: step)
        }
        for body in world.bodies {
            guard let origin = before[body.key] else { continue }
            if simd_distance(origin, body.position) > 1 {
                result.movedBodyCount += 1
            }
        }
        return result
    }

    // MARK: - Report

    private static func report(
        scene: CellScene,
        start: [(key: ReferenceKey, position: SIMD3<Float>)],
        settle: SettleResult,
        shove: ShoveResult,
        world: DynamicBodyWorld
    ) -> String {
        var lines = ["OpenSky dynamic-body probe", ""]
        lines.append("## Cell")
        lines.append("interior: \(WalkPathRoute.farmInterior)")
        lines.append("static shapes: \(scene.staticCollision.stats.shapeCount), "
            + "triangles: \(scene.staticCollision.stats.triangleCount)")
        lines.append("simulated bodies: \(start.count)")
        lines.append("")
        lines.append("## Settle (\(settleSteps) fixed steps)")
        lines.append(String(
            format: "step time: avg %.4f ms, max %.4f ms (budget %.2f ms)",
            settle.averageStepMS, settle.maximumStepMS, budgetMS
        ))
        lines.append("asleep at end: \(settle.sleepingCount) of \(world.bodyCount)")
        lines.append("resting transforms recorded: \(settle.settledTransformCount)")
        lines.append(String(format: "largest drop: %.2f units", settle.maximumDrop))
        lines.append("non-finite poses: \(settle.nonFiniteCount), "
            + "recovered bodies: \(settle.recoveredBodyCount)")
        lines.append("")
        lines.append("## Shove")
        lines.append("woken by the push: \(shove.wokenBodyCount)")
        lines.append("moved more than a unit: \(shove.movedBodyCount)")
        lines.append("")
        lines.append("## Per-body rest (key, drop in units)")
        lines.append("`floor` is a downward sphere cast from the start pose:")
        lines.append("the travel to the first static surface, `overlapping`, or `none`.")
        let resting = Dictionary(
            world.bodies.map { ($0.key, $0.position) }, uniquingKeysWith: { first, _ in first }
        )
        for entry in start.sorted(by: { $0.key < $1.key }).prefix(60) {
            guard let end = resting[entry.key] else { continue }
            let radius = world.body(for: entry.key)?.definition.boundingRadius ?? 0
            let down = ShapeSweepQuery.sphere(
                center: entry.position,
                radius: max(radius * 0.5, 2),
                direction: SIMD3(0, 0, -1),
                maximumDistance: 4096
            )
            let floor = ShapeSweeper.firstHit(
                query: down, shapes: scene.staticCollision.candidates(overlapping: down.bounds)
            )
            lines.append(String(
                format: "  %@ start (%.0f, %.0f, %.0f) r %.1f drop %.2f, floor %@, asleep %@",
                entry.key.description,
                entry.position.x, entry.position.y, entry.position.z,
                radius,
                entry.position.z - end.z,
                Self.describe(floor),
                world.body(for: entry.key)?.isSleeping == true ? "yes" : "no"
            ))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A downward sweep's answer, for the report.
    private static func describe(_ hit: ShapeSweepHit?) -> String {
        guard let hit else { return "none" }
        return hit.startsOverlapping ? "overlapping" : String(format: "%.1f", hit.distance)
    }

    private static func write(report: String) throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let url = directory.appending(path: "dynamic-body-probe.log")
        try report.write(to: url, atomically: true, encoding: .utf8)
        print("[INFO] dynamic-body probe: \(url.path)")
    }
}
