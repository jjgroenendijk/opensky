// End-to-end trigger volumes over the fixed-step path (issue #173): a real
// `WalkController` walks a synthetic path through a scripted volume placed in
// a real `CellStreamer`, and the compiled `OnTriggerEnter`/`OnTriggerLeave`
// bodies run in the Papyrus VM. Also pins the cell-unload containment
// ordering: leave is queued before `detach` retires the instances.
//
// Everything is built in code — REFR records, PEX objects, collision geometry.
// No game content, no Metal.

@testable import opensky
import simd
import Testing

@MainActor
struct M11TriggerVolumeWalkTests {
    private static let volumeID = PapyrusWorldTriggerTests.volumeID
    private static let scriptName = PapyrusWorldTriggerTests.scriptName
    private static var enterNote: String {
        "\(PapyrusRuntime.key(scriptName)).enter"
    }

    private static var leaveNote: String {
        "\(PapyrusRuntime.key(scriptName)).leave"
    }

    private static var center: SIMD3<Float> {
        CellStreamerTests.center
    }

    private struct Harness {
        let session: PapyrusWorldFixture.Session
        let streamer: CellStreamer
        /// Event-queue function names observed at the moment the cell detach
        /// callback ran, which is what pins the leave-before-retire ordering.
        let detachWitness: DetachWitness
    }

    private final class DetachWitness {
        var queuedAtDetach: [String] = []
    }

    /// One resident cell holding a scripted trigger volume, wired to a Papyrus
    /// world exactly as `GameViewController.wirePapyrus` wires it.
    private static func makeHarness(isPersistent: Bool = false) throws -> Harness {
        let entry = try PapyrusWorldFixture.referenceEntry(
            objectID: volumeID,
            scripts: [VMADFixture.Script(scriptName, properties: [])],
            isPersistent: isPersistent
        )
        let volume = try #require(TriggerStreamFixture.boxVolume(
            objectID: volumeID,
            center: center + SIMD3<Float>(0, 0, 64),
            halfExtents: SIMD3(repeating: 64)
        ))
        let session = PapyrusWorldFixture.session(
            objects: [PapyrusWorldTriggerTests.triggerScript()],
            entries: [entry],
            attach: false
        )
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerTests.makeStreamer(runner: runner, radius: 0)
        session.bridge.references = streamer
        let witness = DetachWitness()
        wire(streamer: streamer, session: session, witness: witness)
        integrate(streamer: streamer, runner: runner, entry: entry, volume: volume)
        PapyrusWorldFixture.drain(session.world)
        return Harness(session: session, streamer: streamer, detachWitness: witness)
    }

    private static func wire(
        streamer: CellStreamer,
        session: PapyrusWorldFixture.Session,
        witness: DetachWitness
    ) {
        let world = session.world
        streamer.onCellAttached = { scene, firstIntegration in
            guard let location = scene.location else { return }
            world.attach(
                cell: location,
                references: scene.references,
                formIDResolver: PapyrusWorldFixture.resolver,
                firstIntegration: firstIntegration
            )
        }
        streamer.onCellDetached = { location in
            witness.queuedAtDetach = world.eventQueue.map(\.functionName)
            world.detach(cell: location)
        }
        streamer.onTriggerTransition.add { [weak bridge = session.bridge] event in
            bridge?.handleTriggerTransition(event)
        }
    }

    private static func integrate(
        streamer: CellStreamer,
        runner: ManualCellBuildRunner,
        entry: RuntimeReferenceEntry,
        volume: TriggerVolume
    ) {
        let scene = CellStreamerTests.cellScene(
            location: .exterior(CellStreamerTests.coordinate(0, 0)),
            triggerVolumes: TriggerStreamFixture.volumeSet(
                [volume], location: .exterior(CellStreamerTests.coordinate(0, 0))
            ),
            references: RuntimeReferenceIndex(entries: [entry])
        )
        streamer.update(cameraPosition: center)
        runner.complete(CellStreamerTests.coordinate(0, 0), with: .success(scene))
        streamer.update(cameraPosition: center)
    }

    // MARK: - The fixed-step walk

    /// Walks straight along +x through the volume, one 1/30 s frame at a time,
    /// advancing the VM by the same delta each frame. Returns the frame index
    /// each recorded note first appeared at.
    private static func walkThrough(_ harness: Harness, frames: Int = 200) -> [(Int, String)] {
        var camera = FreeFlyCamera(
            position: TriggerStreamFixture.eye(
                feetAt: center - SIMD3<Float>(300, 0, 0)
            ),
            yaw: 0,
            pitch: 0
        )
        var controller = WalkController(cameraPosition: camera.position)
        var timeline: [(Int, String)] = []
        var seen = 0
        for frame in 0 ..< frames {
            controller.update(
                camera: &camera,
                input: CameraInput(moveForward: 1, dt: 1.0 / 30.0),
                sampleGround: flatGround
            )
            harness.streamer.update(
                cameraPosition: camera.position,
                playerCapsule: PlayerCapsuleState(
                    capsule: controller.capsule,
                    feetPosition: controller.feetPosition
                )
            )
            _ = harness.session.world.advance(delta: 1.0 / 30.0)
            let notes = harness.session.dispatch.notes
            while seen < notes.count {
                timeline.append((frame, notes[seen]))
                seen += 1
            }
        }
        return timeline
    }

    private static func flatGround(_: SIMD2<Float>) -> TerrainGroundSample? {
        TerrainGroundSample(height: 0, normal: SIMD3<Float>(0, 0, 1))
    }

    @Test
    func walkingThroughAScriptedVolumeFiresEnterAndLeaveExactlyOnce() throws {
        let harness = try Self.makeHarness()
        let timeline = Self.walkThrough(harness)
        #expect(timeline.map(\.1) == [Self.enterNote, Self.leaveNote])
        // The leave must land strictly after the enter, with dwell frames in
        // between rather than both firing on one frame.
        let enterFrame = try #require(timeline.first?.0)
        let leaveFrame = try #require(timeline.last?.0)
        #expect(leaveFrame > enterFrame)
        #expect(harness.streamer.occupiedTriggers.isEmpty)
    }

    @Test
    func theSameWalkReplaysIdenticallyFrameForFrame() throws {
        let first = try Self.walkThrough(Self.makeHarness())
        let second = try Self.walkThrough(Self.makeHarness())
        #expect(first.map(\.0) == second.map(\.0))
        #expect(first.map(\.1) == second.map(\.1))
        #expect(first.count == 2)
    }

    // MARK: - Cell-unload containment policy

    /// Standing inside the volume, then unloading its cell.
    private static func occupyThenUnload(_ harness: Harness) {
        harness.streamer.update(
            cameraPosition: TriggerStreamFixture.eye(feetAt: center),
            playerCapsule: TriggerStreamFixture.capsule(feetAt: center)
        )
        // Deliver the enter, so what the detach witness sees is only the leave.
        PapyrusWorldFixture.drain(harness.session.world)
        let departed = CellGridManager.cellCenter(of: CellStreamerTests.coordinate(8, 0))
        harness.streamer.update(
            cameraPosition: TriggerStreamFixture.eye(feetAt: departed),
            playerCapsule: TriggerStreamFixture.capsule(feetAt: departed)
        )
    }

    @Test
    func unloadQueuesTheLeaveBeforeTheDetachRetiresInstances() throws {
        let harness = try Self.makeHarness()
        Self.occupyThenUnload(harness)
        // The witness ran inside `detach`'s call site, before retirement, and
        // already saw the leave queued.
        #expect(harness.detachWitness.queuedAtDetach == ["OnTriggerLeave"])
        #expect(harness.streamer.occupiedTriggers.isEmpty)
    }

    @Test
    func aNonPersistentInstanceLosesTheQueuedLeaveToRetirement() throws {
        let harness = try Self.makeHarness()
        Self.occupyThenUnload(harness)
        PapyrusWorldFixture.drain(harness.session.world)
        // Retirement drops the retired instance's queued events, so the leave
        // is never delivered. It was queued first, which is all the engine can
        // offer a script whose instance is going away.
        #expect(harness.session.dispatch.notes == [Self.enterNote])
        #expect(harness.session.world.instancesByKey.isEmpty)
    }

    @Test
    func aPersistentInstanceSurvivesTheDetachAndReceivesTheLeave() throws {
        let harness = try Self.makeHarness(isPersistent: true)
        Self.occupyThenUnload(harness)
        PapyrusWorldFixture.drain(harness.session.world)
        #expect(harness.session.dispatch.notes == [Self.enterNote, Self.leaveNote])
        #expect(harness.session.world.instancesByKey.count == 1)
    }
}
