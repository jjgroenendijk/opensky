// The rolling trigger-transition log behind World > World > Triggers
// (issue #173): line format, newest-last ordering, the bounded ring, and the
// honest recorded total a truncated ring still reports.

@testable import opensky
import Testing

@MainActor
struct TriggerEventLogTests {
    private let key = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x00AB_CDEF)

    @Test
    func lineNamesThePhaseTheReferenceAndTheFormID() {
        let log = TriggerEventLog()
        log.record(
            TriggerTransitionEvent(reference: key, phase: .enter),
            formID: FormID(0x0001_A2B3)
        )
        #expect(log.lines == ["enter skyrim.esm:ABCDEF 0x0001A2B3"])
    }

    /// A leave fired while the authoring cell unloads has no reference entry
    /// left to resolve, which the line states rather than hiding.
    @Test
    func unresolvedFormIDIsReportedAsUnloaded() {
        let log = TriggerEventLog()
        log.record(TriggerTransitionEvent(reference: key, phase: .leave), formID: nil)
        #expect(log.lines == ["leave skyrim.esm:ABCDEF unloaded"])
    }

    @Test
    func ringKeepsTheNewestRecordsAndStillCountsTheDroppedOnes() {
        let log = TriggerEventLog()
        let total = TriggerEventLog.capacity + 4
        for index in 0 ..< total {
            log.record(
                TriggerTransitionEvent(
                    reference: .plugin(name: "skyrim.esm", objectID: UInt32(index)),
                    phase: .enter
                ),
                formID: nil
            )
        }
        #expect(log.records.count == TriggerEventLog.capacity)
        #expect(log.recordedCount == total)
        // Newest last: the final record is the last one written.
        #expect(log.records.last?.event.reference
            == .plugin(name: "skyrim.esm", objectID: UInt32(total - 1)))
        #expect(log.records.first?.event.reference
            == .plugin(name: "skyrim.esm", objectID: UInt32(total - TriggerEventLog.capacity)))
    }

    @Test
    func clearEmptiesBothTheRingAndTheTotal() {
        let log = TriggerEventLog()
        log.record(TriggerTransitionEvent(reference: key, phase: .enter), formID: nil)
        log.clear()
        #expect(log.lines.isEmpty)
        #expect(log.recordedCount == 0)
    }

    /// The log subscribes to the streamer's own fan-out, so a dispatched edge
    /// reaches it without any app-side wiring.
    @Test
    func streamerRecordsItsOwnTransitions() {
        let streamer = CellStreamerTests.makeStreamer(
            runner: ManualCellBuildRunner(), radius: 0
        )
        streamer.onTriggerTransition(TriggerTransitionEvent(reference: key, phase: .enter))
        #expect(streamer.triggerLog.lines == ["enter skyrim.esm:ABCDEF unloaded"])
    }
}
