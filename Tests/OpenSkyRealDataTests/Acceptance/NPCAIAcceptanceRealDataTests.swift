// Navigation, detection, and combat acceptance on vanilla records: a Whiterun
// resident's packages follow the game clock, its path is the real Chillfurrow
// navmesh through door `0001633D`, detection uses the plugins' constants, and
// the combat machine runs its full arc. It needs no GPU;
// `NPCAIAcceptanceRenderTests` holds the pixel half. The report in `.logs/` holds
// FormIDs, counts, and timings only.

import Foundation
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPerceptionInterface
@testable import OpenSkyPhysics
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import simd
import TagsTesting
import Testing

@Suite(.tags(.acceptance))
@MainActor
struct NPCAIAcceptanceRealDataTests {
    /// Ysolda, whose stack is the one `PackageRealDataTests` pins across a full
    /// day: three distinct packages over twenty-four hours, so "the schedule
    /// decides" is a claim this route can actually fail.
    private static let residentBase = FormID(0x0001_3BAB)
    private static let residentKey = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x13BAB)

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func theWholeChainRunsOverVanillaRecords() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        var lines = ["OpenSky M16 acceptance chain"]

        let packages = try Self.theScheduleDecidesAllDay(root: root, report: &lines)
        let arrival = try Self.theCorridorIsWalkedThroughTheRealDoor(
            root: root, report: &lines
        )
        try Self.theRealConstantsDriveDetectionAndTheFight(
            root: root, at: arrival, packages: packages, report: &lines
        )
        try Self.write(lines)
    }

    // MARK: - The route

    /// Item 16.5 over vanilla records: one resident's own stack, re-selected at
    /// every hour of the day, produces more than one answer and never an empty
    /// one. A stack that selected the same package all day would pass a weaker
    /// check and prove nothing about the schedule.
    private static func theScheduleDecidesAllDay(
        root: GameDataRoot,
        report lines: inout [String]
    ) throws -> PackageStore {
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let store = PackageStore(file: file)
        var runtime = ActorPackageRuntime(store: store)
        try runtime.register(actor: residentKey, base: residentBase)

        var selected: [FormID] = []
        for hour in 0 ..< 24 {
            runtime.forceReevaluate(
                actor: residentKey,
                clock: GameClock(hour: Float(hour)),
                context: ConditionContext()
            )
            let package = try #require(
                runtime.currentPackage(for: residentKey),
                "no package selected at hour \(hour)"
            )
            selected.append(package.package.formID)
        }
        #expect(Set(selected).count > 1, "the whole day selected one package")

        let readout = try #require(runtime.readouts().first)
        #expect(readout.actorBase == residentBase)
        #expect(readout.procedure != nil)
        lines.append(
            "schedule: \(Set(selected).count) distinct packages over 24 hours,"
                + " last \(readout.editorID ?? readout.currentPackage?.description ?? "—")"
        )
        return store
    }

    /// Items 16.1, 16.2 and 16.4 over vanilla geometry: the corridor is the real
    /// navmesh, the crossing is the real door, and the mover walks it to
    /// arrival. Shares `RealNavigationFixture` with the 16.4 evidence suite, so
    /// the gate and the item cannot be walking two different routes.
    private static func theCorridorIsWalkedThroughTheRealDoor(
        root: GameDataRoot,
        report lines: inout [String]
    ) throws -> SIMD3<Float> {
        var route = try RealNavigationFixture.route(root: root)
        let result = route.graph.findPath(NavigationPathQuery(
            start: route.start, target: route.target
        ))
        guard case let .path(path) = result else {
            Issue.record("the real exterior-to-interior corridor missed")
            throw NPCAIRealDataError.noPath
        }
        #expect(path.doorCrossings.map(\.door) == [WalkPathRoute.farmDoor])

        var runtime = NPCMovementRuntime()
        var crossings: [FormID] = []
        runtime.onDoorCrossing = { _, door in crossings.append(door) }
        let started = runtime.start(NPCMoveStart(
            actor: residentKey,
            formID: residentBase,
            placement: PlacedReference.Placement(position: path.waypoints[0], rotation: .zero),
            scale: 1,
            capsule: .standard,
            configuration: PlayerMovementConfiguration.resolve(
                store: GameSettingLoader.load(root: root),
                movementTypes: MovementTypeLoader.load(root: root)
            ),
            path: path
        ))
        #expect(started)

        let world = RealNavigationFixture.movementWorld(path: path, graph: route.graph)
        let startedAt = DispatchTime.now().uptimeNanoseconds
        for _ in 0 ..< 2400 where runtime.activeMoverCount > 0 {
            runtime.advance(by: 1 / 60, world: world)
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000

        let readout = try #require(runtime.readouts().first)
        #expect(readout.state == .arrived)
        #expect(crossings == [WalkPathRoute.farmDoor])
        lines.append(
            "corridor: \(path.waypoints.count) waypoints,"
                + " \(path.stats.corridorTriangleCount) triangles,"
                + " \(path.stats.nodesExpanded) expansions,"
                + " door \(WalkPathRoute.farmDoor), \(elapsed) ms offscreen"
        )
        return readout.feetPosition
    }

    /// Items 16.6 and 16.7 over vanilla constants: the detection settings and
    /// the combat settings both resolve out of the install rather than from
    /// OpenSky defaults, and the whole entry-to-resume arc runs against them at
    /// the place the mover actually stopped.
    private static func theRealConstantsDriveDetectionAndTheFight(
        root: GameDataRoot,
        at arrival: SIMD3<Float>,
        packages: PackageStore,
        report lines: inout [String]
    ) throws {
        let settings = GameSettingLoader.load(root: root)
        let detection = DetectionSettings.resolve(store: settings)
        let combatSettings = CombatSettings.resolve(store: settings)
        let plugins = detection.report.filter { $0.setting.source.hasSuffix(".esm") }
        #expect(!plugins.isEmpty, "every detection constant fell back to an OpenSky default")

        let chain = NPCAIRealDataFight(
            detection: detection,
            combat: combatSettings,
            actor: residentKey,
            actorFeet: arrival
        )
        chain.playerFeet = arrival + SIMD3(96, 0, 0)

        #expect(
            chain.run(frames: 1200) { chain.detectionState == .detected },
            "the resident never noticed a player running at it under vanilla constants"
        )
        chain.setHostile(true)
        #expect(
            chain.run(frames: 1800) { chain.phase?.isEngaged == true },
            "a hostile resident that had detected the player never entered the fight"
        )

        chain.blockSight = true
        #expect(
            chain.run(frames: 2400) { chain.phase == .searching },
            "the resident never went looking for a player it had lost"
        )
        #expect(
            chain.run(frames: 3600) { chain.phase == .disengaged },
            "the resident searched forever instead of giving up"
        )
        #expect(chain.packageResumes == [residentKey])
        #expect(packages.package(FormID(0x0002_C3BA)) != nil, "the stack is still readable")

        lines.append(
            "detection: \(plugins.count) of \(detection.report.count) constants from plugins;"
                + " fight reached \(chain.visitedPhases.count) phases,"
                + " \(chain.stepCount) fixed steps"
        )
    }

    // MARK: - Report

    /// FormIDs, counts and timings only. Nothing game-derived leaves the
    /// gitignored run directory.
    private static func write(_ lines: [String]) throws {
        let directory = try RepositoryLogs.directory()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        try (lines.joined(separator: "\n") + "\n").write(
            to: directory.appending(path: "m16-acceptance-chain.log"),
            atomically: true,
            encoding: .utf8
        )
    }
}

/// Thrown only to end the run early when the real corridor misses, which
/// `Issue.record` has already reported.
private enum NPCAIRealDataError: Error {
    case noPath
}
