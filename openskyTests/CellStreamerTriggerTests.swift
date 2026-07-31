// Per-frame trigger-volume occupancy in the streamer (issue #173): edge
// events, dwelling, teleport-through, the walk-mode gate, a volume straddling
// a streaming boundary, and the cell-unload containment policy.
//
// Synthetic cell scenes through a manual build runner — no Metal, no game
// data, no Papyrus VM (the VM half lives in PapyrusWorldTriggerTests).

@testable import opensky
import simd
import Testing

@MainActor
struct CellStreamerTriggerTests {
    private static let volumeID: UInt32 = 0x501
    /// World centre of cell (0,0), where the single-cell fixtures put the box.
    private static var center: SIMD3<Float> {
        CellStreamerTests.center
    }

    private struct Harness {
        let runner: ManualCellBuildRunner
        let streamer: CellStreamer
        let recorder: TriggerRecorder
    }

    /// Records occupancy edges and cell detaches in one ordered log, so a test
    /// can assert that a leave was emitted *before* the detach it precedes.
    private final class TriggerRecorder {
        var log: [String] = []

        func note(_ event: TriggerTransitionEvent) {
            log.append(event.phase == .enter ? "enter" : "leave")
        }
    }

    /// Single resident cell (radius 0) holding one box volume around the cell
    /// centre, already integrated.
    private static func makeHarness() throws -> Harness {
        let volume = try #require(TriggerStreamFixture.boxVolume(
            objectID: volumeID,
            center: center + SIMD3<Float>(0, 0, 64)
        ))
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerTests.makeStreamer(runner: runner, radius: 0)
        let recorder = TriggerRecorder()
        streamer.onTriggerTransition.add { recorder.note($0) }
        let scene = CellStreamerTests.cellScene(
            location: .exterior(CellStreamerTests.coordinate(0, 0)),
            triggerVolumes: TriggerStreamFixture.volumeSet([volume])
        )
        streamer.update(cameraPosition: center)
        runner.complete(CellStreamerTests.coordinate(0, 0), with: .success(scene))
        streamer.update(cameraPosition: center)
        return Harness(runner: runner, streamer: streamer, recorder: recorder)
    }

    /// One frame with the capsule's feet at `feet`, in walk mode.
    private static func step(_ harness: Harness, feetAt feet: SIMD3<Float>) {
        harness.streamer.update(
            cameraPosition: TriggerStreamFixture.eye(feetAt: feet),
            playerCapsule: TriggerStreamFixture.capsule(feetAt: feet)
        )
    }

    private static var inside: SIMD3<Float> {
        center
    }

    private static var outside: SIMD3<Float> {
        center + SIMD3<Float>(600, 0, 0)
    }

    private static var farSide: SIMD3<Float> {
        center - SIMD3<Float>(600, 0, 0)
    }

    // MARK: - Edge events

    @Test
    func enteringAVolumeFiresEnterOnceAndDwellingFiresNothingMore() throws {
        let harness = try Self.makeHarness()
        Self.step(harness, feetAt: Self.outside)
        #expect(harness.recorder.log.isEmpty)

        Self.step(harness, feetAt: Self.inside)
        #expect(harness.recorder.log == ["enter"])
        #expect(harness.streamer.occupiedTriggers == [TriggerStreamFixture.key(Self.volumeID)])

        // Dwelling: several frames inside, including a small move that stays
        // inside, must not re-fire.
        Self.step(harness, feetAt: Self.inside)
        Self.step(harness, feetAt: Self.inside + SIMD3<Float>(16, 0, 0))
        Self.step(harness, feetAt: Self.inside)
        #expect(harness.recorder.log == ["enter"])
    }

    @Test
    func leavingAVolumeFiresLeaveOnce() throws {
        let harness = try Self.makeHarness()
        Self.step(harness, feetAt: Self.inside)
        Self.step(harness, feetAt: Self.outside)
        #expect(harness.recorder.log == ["enter", "leave"])
        #expect(harness.streamer.occupiedTriggers.isEmpty)

        Self.step(harness, feetAt: Self.outside)
        Self.step(harness, feetAt: Self.outside + SIMD3<Float>(64, 0, 0))
        #expect(harness.recorder.log == ["enter", "leave"])
    }

    @Test
    func teleportingAcrossAVolumeFiresEnterThenLeaveInOneFrame() throws {
        let harness = try Self.makeHarness()
        Self.step(harness, feetAt: Self.outside)
        #expect(harness.recorder.log.isEmpty)

        // One frame jumps clean past the box: neither endpoint is inside it,
        // so only the swept samples can see the visit.
        Self.step(harness, feetAt: Self.farSide)
        #expect(harness.recorder.log == ["enter", "leave"])
        #expect(harness.streamer.occupiedTriggers.isEmpty)
    }

    @Test
    func aFrameThatSwapsVolumesFiresTheEnterBeforeTheLeave() throws {
        let volumes = try [
            #require(TriggerStreamFixture.boxVolume(
                objectID: 0x600, center: Self.center + SIMD3<Float>(0, 0, 64)
            )),
            #require(TriggerStreamFixture.boxVolume(
                objectID: 0x601, center: Self.center + SIMD3<Float>(4000, 0, 64)
            ))
        ]
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerTests.makeStreamer(runner: runner, radius: 1)
        var log: [TriggerTransitionEvent] = []
        streamer.onTriggerTransition.add { log.append($0) }
        TriggerStreamFixture.settle(
            streamer: streamer, runner: runner, eye: Self.center
        ) { coordinate in
            CellStreamerTests.cellScene(
                location: .exterior(coordinate),
                triggerVolumes: coordinate == CellStreamerTests.coordinate(0, 0)
                    ? TriggerStreamFixture.volumeSet(volumes)
                    : .empty
            )
        }
        streamer.update(
            cameraPosition: TriggerStreamFixture.eye(feetAt: Self.center),
            playerCapsule: TriggerStreamFixture.capsule(feetAt: Self.center)
        )
        log.removeAll()

        // A jump straight from one box into the other: the sweep samples the
        // gap, so both boxes are touched, but only the second is occupied.
        let destination = Self.center + SIMD3<Float>(4000, 0, 0)
        streamer.update(
            cameraPosition: TriggerStreamFixture.eye(feetAt: destination),
            playerCapsule: TriggerStreamFixture.capsule(feetAt: destination)
        )
        #expect(log.map(\.phase) == [.enter, .leave])
        #expect(log.first?.reference == TriggerStreamFixture.key(0x601))
        #expect(log.last?.reference == TriggerStreamFixture.key(0x600))
    }

    // MARK: - Walk-mode gate

    @Test
    func flyModeFiresNothingAndFreezesOccupancy() throws {
        let harness = try Self.makeHarness()
        // No capsule state at all -- the fly-mode call shape.
        harness.streamer.update(cameraPosition: TriggerStreamFixture.eye(feetAt: Self.inside))
        harness.streamer.update(cameraPosition: TriggerStreamFixture.eye(feetAt: Self.outside))
        #expect(harness.recorder.log.isEmpty)
        #expect(harness.streamer.occupiedTriggers.isEmpty)

        // Walking into the volume, then switching to fly, keeps containment:
        // the player never left, so no leave is fabricated.
        Self.step(harness, feetAt: Self.inside)
        harness.streamer.update(cameraPosition: TriggerStreamFixture.eye(feetAt: Self.inside))
        #expect(harness.recorder.log == ["enter"])
        #expect(harness.streamer.occupiedTriggers.count == 1)
    }

    // MARK: - Streaming boundary

    @Test
    func aVolumeStraddlingACellEdgeFiresFromTheNeighbouringCell() throws {
        // The box is authored in cell (1,0) but reaches back across the x
        // boundary, so the player standing in cell (0,0) is inside it.
        let boundaryX = TerrainMeshBuilder.cellSize
        let volume = try #require(TriggerStreamFixture.boxVolume(
            objectID: Self.volumeID,
            center: SIMD3<Float>(boundaryX, Self.center.y, 64),
            halfExtents: SIMD3<Float>(256, 256, 128)
        ))
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerTests.makeStreamer(runner: runner, radius: 1)
        var log: [TriggerTransitionEvent] = []
        streamer.onTriggerTransition.add { log.append($0) }
        let away = SIMD3<Float>(boundaryX - 600, Self.center.y, 0)
        TriggerStreamFixture.settle(
            streamer: streamer, runner: runner, eye: TriggerStreamFixture.eye(feetAt: away)
        ) { coordinate in
            CellStreamerTests.cellScene(
                location: .exterior(coordinate),
                triggerVolumes: coordinate == CellStreamerTests.coordinate(1, 0)
                    ? TriggerStreamFixture.volumeSet([volume], location: .exterior(coordinate))
                    : .empty
            )
        }
        streamer.update(
            cameraPosition: TriggerStreamFixture.eye(feetAt: away),
            playerCapsule: TriggerStreamFixture.capsule(feetAt: away)
        )
        #expect(log.isEmpty)

        // Still in cell (0,0), now inside the neighbouring cell's volume.
        let straddling = SIMD3<Float>(boundaryX - 100, Self.center.y, 0)
        streamer.update(
            cameraPosition: TriggerStreamFixture.eye(feetAt: straddling),
            playerCapsule: TriggerStreamFixture.capsule(feetAt: straddling)
        )
        #expect(streamer.grid.center == CellStreamerTests.coordinate(0, 0))
        #expect(log.map(\.phase) == [.enter])
        #expect(log.first?.reference == TriggerStreamFixture.key(Self.volumeID))
    }

    // MARK: - Cell unload containment policy

    @Test
    func unloadingTheCellFiresLeaveBeforeTheDetach() throws {
        let harness = try Self.makeHarness()
        let recorder = harness.recorder
        harness.streamer.onCellDetached = { _ in recorder.log.append("detach") }
        Self.step(harness, feetAt: Self.inside)
        #expect(recorder.log == ["enter"])

        // Walk far enough that cell (0,0) leaves the grid entirely.
        let departed = CellGridManager.cellCenter(of: CellStreamerTests.coordinate(8, 0))
        Self.step(harness, feetAt: departed)
        #expect(recorder.log == ["enter", "leave", "detach"])
        #expect(harness.streamer.occupiedTriggers.isEmpty)

        // Containment was released once, not once per later frame.
        Self.step(harness, feetAt: departed)
        #expect(recorder.log == ["enter", "leave", "detach"])
    }

    // MARK: - Sweep sampling

    @Test
    func aNormalWalkingFrameNeedsNoSweepSamples() {
        let samples = CellStreamer.sweepSamples(
            from: .zero, to: SIMD3<Float>(12, 0, 0), radius: PlayerCapsule.standard.radius
        )
        #expect(samples.isEmpty)
    }

    @Test
    func aLongTeleportSamplesAtMostTheCappedNumberOfPoses() throws {
        let samples = CellStreamer.sweepSamples(
            from: .zero,
            to: SIMD3<Float>(1_000_000, 0, 0),
            radius: PlayerCapsule.standard.radius
        )
        #expect(samples.count == CellStreamer.maximumTriggerSweepSamples)
        // Evenly spaced, endpoints excluded, ascending along the path.
        let first = try #require(samples.first)
        let last = try #require(samples.last)
        #expect(first.x > 0)
        #expect(last.x < 1_000_000)
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0.x < $1.x })
    }
}
