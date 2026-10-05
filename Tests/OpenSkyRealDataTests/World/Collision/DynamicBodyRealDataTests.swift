// Env-gated dynamic-body probe over the user's install. It checks what the
// synthetic suites cannot: a vanilla interior yields bodies from its own Havok
// data, they settle, a shove moves them, and a step fits the frame budget. The
// report holds counts and timings and goes to gitignored `.logs/`. Run with
// `make test-real T='DynamicBodyRealDataTests/settlesAndPushesVanillaClutter()'`,
// or `make test-real PERF=1` for the optimized budget.

import Foundation
import Metal
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct DynamicBodyRealDataTests {
    /// Wall-clock budget for one 1/120 s physics step, in milliseconds. An
    /// optimized build (`make test-real PERF=1`) is held to 2 ms; measured 0.37.
    /// `-Onone` runs about 24x slower, so a plain `make test-real` gets 20 ms.
    private static var budgetMS: Double {
        #if OPENSKY_OPTIMIZED
            2.0
        #else
            20.0
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

    @Test(.enabled(if: RealDataEnvironment.canRender), .tags(.perf, .slow))
    func settlesAndPushesVanillaClutter() throws {
        let builder = try RealDataInstall.load().sceneBuilder(readsLooseFiles: true)
        builder.simulatesDynamicBodies = true
        let scene = try builder.buildInteriorScene(cellFormID: WalkPathRoute.farmInterior)

        let placements = scene.dynamicBodies
        #expect(!placements.isEmpty, "the vanilla farmhouse placed no simulated body")
        // The drawn half of the same claim: a reference the solver
        // moves has to carry its identity into the draw list, or the pose
        // produced below never reaches the screen and the clutter simulates
        // invisibly. Asserted on real placements because the tagging is done
        // against the cell build's own resolved instances.
        let drawn = Set(
            (scene.renderScene.opaque + scene.renderScene.alphaTested)
                .flatMap(\.instances)
                .map(\.referenceFormID)
        )
        let untagged = placements.filter { !drawn.contains($0.reference.rawValue) }
        #expect(untagged.isEmpty, "\(untagged.count) simulated references draw untagged")
        var world = DynamicBodyWorld()
        world.setCell(.interior(WalkPathRoute.farmInterior), placements: placements)
        let start = world.bodies.map { (key: $0.key, position: $0.position) }

        let settle = try Self.settle(world: &world, scene: scene)
        let shove = Self.shove(world: &world, scene: scene)

        try Self.write(name: "interior", report: Self.report(
            scene: scene, start: start, settle: settle, shove: shove, world: world
        ))

        #expect(settle.nonFiniteCount == 0, "a body integrated to a non-finite pose")
        #expect(settle.recoveredBodyCount == 0, "a body had to be reset mid-step")
        // Every simulated reference comes to rest within five seconds of world
        // time, near where it was authored. Both checks are needed: clutter that
        // falls out of the world and clutter that never sleeps each pass one.
        #expect(
            settle.sleepingCount == world.bodyCount,
            "\(world.bodyCount - settle.sleepingCount) of \(world.bodyCount) never came to rest"
        )
        #expect(
            settle.maximumDrop < Self.maximumSettledDropUnits,
            "a body fell \(settle.maximumDrop) units out of the geometry it was authored in"
        )
        #expect(shove.movedBodyCount > 0, "a shove moved nothing")
        // And what the renderer would be handed after all that is non-empty:
        // clutter that settled away from where the plugin authored it is drawn
        // by its live pose until a rebuild bakes it in.
        #expect(!world.instanceDeltas.isEmpty, "no body published a pose to draw by")
        #expect(
            settle.averageStepMS <= Self.budgetMS,
            "physics step averaged \(settle.averageStepMS) ms against a \(Self.budgetMS) ms budget"
        )
    }
}

extension DynamicBodyRealDataTests {
    /// Exterior acceptance: take a vanilla dynamic placement and its tagged draw,
    /// push it across a real adjacent-cell boundary, then remove the placing
    /// cell while the occupied cell remains.
    @Test(.enabled(if: RealDataEnvironment.canRender))
    func rebinsVanillaExteriorClutterAcrossResidentCells() throws {
        let builder = try RealDataInstall.load().sceneBuilder(readsLooseFiles: true)
        builder.simulatesDynamicBodies = true
        try Self.runExteriorProbe(builder: builder)
    }

    private static func runExteriorProbe(builder: CellSceneBuilder) throws {
        let pair = try Self.exteriorPair(builder: builder)
        let placement = pair.source.dynamicBodies[0]
        let sourceLocation = CellSceneLocation.exterior(pair.sourceCoordinate)
        let destinationLocation = CellSceneLocation.exterior(pair.destinationCoordinate)
        var world = DynamicBodyWorld()
        world.setCell(sourceLocation, placements: [placement])
        world.setCell(destinationLocation, placements: [])
        let start = try #require(world.body(for: placement.key)?.position)
        let direction = Self.direction(
            from: pair.sourceCoordinate, to: pair.destinationCoordinate
        )
        Self.push(body: placement.key, direction: direction, world: &world)

        let emptyWorld = DynamicStepWorld(staticCandidates: { _ in [] })
        for _ in 0 ..< 600 where world.body(for: placement.key)?.occupiedCell == sourceLocation {
            world.advance(by: WalkController.fixedTimeStep, world: emptyWorld)
        }
        let crossed = try #require(world.body(for: placement.key))
        #expect(crossed.occupiedCell == destinationLocation, "body did not cross the boundary")
        #expect(world.instanceDeltas[placement.reference.rawValue] != nil)

        var composition = CellSceneComposition()
        composition.setCell(pair.source, at: pair.sourceCoordinate)
        composition.setCell(pair.destination, at: pair.destinationCoordinate)
        _ = composition.setDynamicDrawOwnership(world.exteriorDrawOwnership)
        let beforeDraws = Self.drawCount(
            reference: placement.reference, in: composition.composedScene()
        )
        composition.removeCell(at: pair.sourceCoordinate)
        world.removeCell(sourceLocation)
        let afterSourceUnload = Self.drawCount(
            reference: placement.reference, in: composition.composedScene()
        )
        let beforeContinuation = try #require(world.body(for: placement.key)?.position)
        world.advance(by: WalkController.fixedTimeStep, world: emptyWorld)

        #expect(world.body(for: placement.key) != nil)
        #expect(world.body(for: placement.key)?.position != beforeContinuation)
        #expect(beforeDraws > 0, "vanilla dynamic reference had no tagged draw")
        #expect(afterSourceUnload == beforeDraws, "draw duplicated or vanished on handoff")

        composition.removeCell(at: pair.destinationCoordinate)
        world.removeCell(destinationLocation)
        let afterDestinationUnload = Self.drawCount(
            reference: placement.reference, in: composition.composedScene()
        )
        #expect(world.body(for: placement.key) == nil)
        #expect(afterDestinationUnload == 0)
        try Self.write(name: "exterior-rebin", report: """
        OpenSky exterior dynamic-body re-bin probe

        placing cell: \(pair.sourceCoordinate)
        occupied cell: \(pair.destinationCoordinate)
        reference: \(placement.reference)
        start: \(start)
        crossed: \(crossed.position)
        draw instances before unload: \(beforeDraws)
        draw instances after placing-cell unload: \(afterSourceUnload)
        draw instances after occupied-cell unload: \(afterDestinationUnload)
        simulated after placing-cell unload: yes
        retired after occupied-cell unload: yes
        """)
    }
}

extension DynamicBodyRealDataTests {
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

    /// Walks a capsule into settled clutter and counts what moved. The capsule
    /// starts just outside each of the first `shovedBodyCount` bodies in key
    /// order, because the centroid of a room's clutter is usually mid-air.
    /// Key order keeps the choice deterministic.
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

    private static func write(name: String, report: String) throws {
        let environment = ProcessInfo.processInfo.environment
        let directory = try environment["OPENSKY_RUN_DIR"].map(URL.init(fileURLWithPath:))
            ?? RepositoryLogs.directory("test-real/latest").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let url = directory.appending(path: "dynamic-body-\(name).log")
        try report.write(to: url, atomically: true, encoding: .utf8)
        print("[INFO] dynamic-body probe: \(url.path)")
    }
}
