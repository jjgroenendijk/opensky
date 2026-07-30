// Script-instance lifetime across cell streaming (issue #171): instances are
// created when a cell first integrates, survive a world-state rebuild without
// re-firing load events, are retired when the cell unloads, stay silent while
// a coverage transition stages them offscreen, and survive an interior
// rebuild.
//
// The streamer, the world-state store and the Papyrus world runtime are wired
// together exactly as `GameViewController.wirePapyrus` wires them, over
// synthetic VMAD references and a synthetic script. No Metal, no game data.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct CellStreamerPapyrusTests {
    private static let scriptName = "TestScript"
    private static let referenceID: UInt32 = 0x101

    private struct Harness {
        let store: WorldStateStore
        let runner: ManualCellBuildRunner
        let streamer: CellStreamer
        let world: PapyrusWorldRuntime
        let probe: PapyrusWorldProbeDispatch
    }

    private static func makeHarness(radius: Int32 = 0) -> Harness {
        let probe = PapyrusWorldProbeDispatch()
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [PapyrusWorldFixture.fullEventScript(scriptName)],
            nativeDispatch: probe
        )
        let store = WorldStateStore()
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerTests.makeStreamer(runner: runner, radius: radius)
        streamer.stateSource = { store.snapshot() }
        store.onMutation = { [weak streamer] location, sequence in
            streamer?.noteStateMutation(in: location, sequence: sequence)
        }
        let resolver = PapyrusWorldFixture.resolver
        streamer.onCellAttached = { scene, firstIntegration in
            guard let location = scene.location else { return }
            world.attach(
                cell: location,
                references: scene.references,
                formIDResolver: resolver,
                firstIntegration: firstIntegration
            )
        }
        streamer.onCellDetached = { world.detach(cell: $0) }
        return Harness(
            store: store, runner: runner, streamer: streamer, world: world, probe: probe
        )
    }

    private static func scriptedScene(
        at coordinate: CellCoordinate,
        stateSequence: UInt64 = 0
    ) throws -> CellScene {
        let entry = try PapyrusWorldFixture.referenceEntry(
            objectID: referenceID,
            scripts: [VMADFixture.Script(scriptName, properties: [])]
        )
        return CellStreamerTests.cellScene(
            location: .exterior(coordinate),
            references: PapyrusWorldFixture.index([entry]),
            stateSequence: stateSequence
        )
    }

    private static func position(of coordinate: CellCoordinate) -> SIMD3<Float> {
        CellGridManager.cellCenter(of: coordinate)
    }

    private static let origin = CellCoordinate(x: 0, y: 0)

    private static let loadNotes = [
        "testscript.oninit", "testscript.oncellattach", "testscript.onload"
    ]

    /// Streams the origin cell in and drains the events it enqueued.
    private static func settleFirstIntegration(_ harness: Harness) throws {
        harness.streamer.update(cameraPosition: position(of: origin))
        try harness.runner.complete(origin, with: .success(scriptedScene(at: origin)))
        harness.streamer.update(cameraPosition: position(of: origin))
        PapyrusWorldFixture.drain(harness.world)
    }

    // MARK: - First integration

    @Test
    func firstIntegrationInstantiatesScriptsAndFiresLoadEvents() throws {
        let harness = Self.makeHarness()
        try Self.settleFirstIntegration(harness)

        #expect(harness.world.instancesByKey.count == 1)
        let key = PapyrusWorldFixture.key(objectID: Self.referenceID, script: Self.scriptName)
        #expect(harness.world.instancesByKey[key] != nil)
        #expect(harness.probe.notes == Self.loadNotes)
    }

    // MARK: - Rebuild

    @Test
    func aWorldStateRebuildKeepsInstancesAndFiresNothing() throws {
        let harness = Self.makeHarness()
        try Self.settleFirstIntegration(harness)
        let handle = try #require(harness.world.instancesByKey.values.first)

        // A mutation attributed to the cell requeues it; the rebuilt scene
        // replaces the resident one at the same coordinate.
        harness.store.set(
            ReferenceEnableState.disabled,
            for: .plugin(name: PapyrusWorldFixture.pluginName, objectID: 0x900),
            in: .exterior(Self.origin)
        )
        harness.streamer.update(cameraPosition: Self.position(of: Self.origin))
        let sequence = harness.store.nextJournalSequence
        try harness.runner.complete(
            Self.origin,
            with: .success(Self.scriptedScene(at: Self.origin, stateSequence: sequence))
        )
        harness.streamer.update(cameraPosition: Self.position(of: Self.origin))
        PapyrusWorldFixture.drain(harness.world)

        #expect(harness.world.instancesByKey.count == 1)
        // Same handle -> the instance was reconciled, not recreated.
        #expect(harness.world.instancesByKey.values.first == handle)
        #expect(harness.probe.notes == Self.loadNotes)
    }

    // MARK: - Unload

    @Test
    func unloadingACellRetiresItsInstances() throws {
        let harness = Self.makeHarness()
        try Self.settleFirstIntegration(harness)
        #expect(harness.world.instancesByKey.count == 1)

        // Walk far enough that the origin leaves the grid entirely.
        harness.streamer.update(
            cameraPosition: Self.position(of: CellCoordinate(x: 8, y: 0))
        )
        #expect(harness.world.instancesByKey.isEmpty)
        PapyrusWorldFixture.drain(harness.world)
        #expect(harness.probe.notes == Self.loadNotes)
    }

    // MARK: - Coverage transition

    @Test
    func stagedCoverageCellsAttachOnlyWhenTheTransitionCommits() throws {
        let harness = Self.makeHarness()
        try Self.settleFirstIntegration(harness)
        harness.runner.completeDistantLOD(Self.origin, with: Self.lodScene())
        harness.streamer.update(cameraPosition: Self.position(of: Self.origin))

        // Recentering with settled coverage stages the new cell offscreen.
        let moved = CellCoordinate(x: 4, y: 0)
        harness.streamer.update(cameraPosition: Self.position(of: moved))
        #expect(harness.streamer.isCoverageTransitionActive)
        try harness.runner.complete(moved, with: .success(Self.scriptedScene(at: moved)))
        harness.streamer.update(cameraPosition: Self.position(of: moved))
        PapyrusWorldFixture.drain(harness.world)
        // The staged cell is not in the world yet, so nothing new attached and
        // the departed origin cell is gone.
        #expect(harness.world.attachedByCell[.exterior(moved)] == nil)
        #expect(harness.probe.notes == Self.loadNotes)

        harness.runner.completeDistantLOD(moved, with: Self.lodScene())
        harness.streamer.update(cameraPosition: Self.position(of: moved))
        #expect(!harness.streamer.isCoverageTransitionActive)
        PapyrusWorldFixture.drain(harness.world)
        #expect(harness.world.attachedByCell[.exterior(moved)]?.count == 1)
        #expect(harness.probe.notes == Self.loadNotes + Self.loadNotes.dropFirst())
    }

    private static func lodScene() -> DistantLODScene {
        DistantLODScene(
            renderScene: RenderScene(instances: []),
            assets: CellAssets(),
            blockCount: 1,
            missingBlockCount: 0
        )
    }

    // MARK: - Interior transitions

    @Test
    func enteringAnInteriorAttachesItAndARebuildDoesNot() throws {
        let harness = Self.makeHarness()
        let entry = try PapyrusWorldFixture.referenceEntry(
            objectID: Self.referenceID,
            scripts: [VMADFixture.Script(Self.scriptName, properties: [])]
        )
        let interior = CellStreamerTests.cellScene(
            location: .interior(FormID(0x2000)),
            references: PapyrusWorldFixture.index([entry])
        )
        harness.streamer.apply(transition: Self.transition(to: interior))
        PapyrusWorldFixture.drain(harness.world)
        #expect(harness.probe.notes == Self.loadNotes)
        let handle = try #require(harness.world.instancesByKey.values.first)

        // Re-running the same transition as a rebuild swaps the scene under a
        // stationary player: same instance, no second OnLoad.
        harness.streamer.apply(transition: Self.transition(to: interior), isRebuild: true)
        PapyrusWorldFixture.drain(harness.world)
        #expect(harness.world.instancesByKey.count == 1)
        #expect(harness.world.instancesByKey.values.first == handle)
        #expect(harness.probe.notes == Self.loadNotes)
    }

    private static func transition(to scene: CellScene) -> DoorTransition {
        DoorTransition(
            sourceDoor: FormID(0x10),
            destinationDoor: FormID(0x20),
            destinationPlacement: PlacedReference.Placement(
                position: SIMD3(1, 2, 3), rotation: .zero
            ),
            scene: scene
        )
    }
}
