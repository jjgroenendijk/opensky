// Exclusive phase timing: a nested phase takes its time out of the outer one.

import Foundation
import GameDataTesting
import OpenSkyGameData
import Synchronization
import Testing

struct LoadPhaseRecorderTests {
    /// A clock that returns the given readings in order, one per call.
    private static func clock(_ readings: [UInt64]) -> @Sendable () -> UInt64 {
        let remaining = Mutex(readings)
        return { remaining.withLock { $0.isEmpty ? 0 : $0.removeFirst() } }
    }

    @Test
    func nestedPhaseTimeIsTakenOutOfTheOuterPhase() {
        // mesh starts at 0 ms, archive runs 2 to 5 ms, mesh ends at 10 ms.
        let recorder = LoadPhaseRecorder(now: Self.clock([0, 2_000_000, 5_000_000, 10_000_000]))
        recorder.measure(.mesh) {
            recorder.measure(.archive) {}
        }
        let times = recorder.snapshot()
        #expect(times.meshMS == 7)
        #expect(times.archiveMS == 3)
        #expect(times.measuredMS == 10)
    }

    @Test
    func aThrowingBodyStillRecordsAndClosesItsMeasurement() {
        struct Failure: Error {}
        let recorder = LoadPhaseRecorder(now: Self.clock([0, 4_000_000, 10_000_000, 11_000_000]))
        #expect(throws: Failure.self) {
            try recorder.measure(.texture) { throw Failure() }
        }
        recorder.measure(.collision) {}
        let times = recorder.snapshot()
        #expect(times.textureMS == 4)
        #expect(times.collisionMS == 1)
    }

    @Test
    func resetClearsTheTotals() {
        let recorder = LoadPhaseRecorder(now: Self.clock([0, 1_000_000]))
        recorder.measure(.archive) {}
        recorder.reset()
        #expect(recorder.snapshot() == LoadPhaseTimes())
    }

    @Test
    func noRecorderRunsTheBodyDirectly() {
        let recorder: LoadPhaseRecorder? = nil
        #expect(recorder.measure(.mesh) { 42 } == 42)
    }

    @Test
    func completedTimesGiveTheUnclaimedRestToOther() {
        let times = LoadPhaseTimes(archiveMS: 10, textureMS: 20, meshMS: 30, collisionMS: 5)
        #expect(times.completed(totalMS: 100).otherMS == 35)
        #expect(times.completed(totalMS: 50).otherMS == 0)
    }

    @Test
    func timedFileSourceBooksReadsToArchive() throws {
        let recorder = LoadPhaseRecorder(now: Self.clock([0, 3_000_000, 3_000_000, 4_000_000]))
        let source = PhaseTimedFileSource(
            base: InMemoryFileSource(files: ["meshes\\cup.nif": Data([1, 2, 3])]),
            recorder: recorder
        )
        #expect(try source.contents(forPath: "Meshes/Cup.nif") == Data([1, 2, 3]))
        #expect(source.exists("meshes\\cup.nif"))
        #expect(recorder.snapshot().archiveMS == 4)
    }
}
