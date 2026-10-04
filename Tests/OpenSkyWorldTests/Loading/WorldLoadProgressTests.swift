// Stage reporting: a start and a finish per stage, and no stage after a cancel.

@testable import OpenSkyWorld
import Synchronization
import Testing

struct WorldLoadProgressTests {
    @Test
    func reportsStartThenFinishAndReturnsTheValue() throws {
        let events = Mutex<[WorldLoadEvent]>([])
        let progress = WorldLoadProgress { event in events.withLock { $0.append(event) } }

        let value = try progress.measure(.dialogue) { 42 }

        #expect(value == 42)
        let recorded = events.withLock(\.self)
        #expect(recorded.count == 2)
        #expect(recorded.first == WorldLoadEvent(stage: .dialogue, kind: .started))
        #expect(recorded.last?.stage == .dialogue)
    }

    @Test
    func cancelledTaskStartsNoStage() async {
        let events = Mutex<[WorldLoadEvent]>([])
        let progress = WorldLoadProgress { event in events.withLock { $0.append(event) } }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try progress.measure(.packages) { 1 }
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        let recorded = events.withLock(\.self)
        #expect(recorded.isEmpty)
    }
}
