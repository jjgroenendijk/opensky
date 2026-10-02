// Plain-value fake for `RuntimeStateCoordinatorTests`: one optional resident
// reference, an optional clock, and a save store held in memory.

@testable import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyAudio
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
@testable import OpenSkyWorldState

enum FakeSaveError: Error {
    case unwritable
}

final class FakeRuntimeStateWorld: RuntimeStateWorld {
    var entries: [RuntimeReferenceEntry] = []
    var crosshairReference: FormID?
    var gameClock: GameClock?
    var timescale: Float?
    var isWorldSimPaused = false
    var musicStore: MusicRecordStore?
    private(set) var timeOfDayWrites: [Float] = []
    private(set) var persistedHours: [Float] = []
    private(set) var projectedGlobals: [(GameClock.TimeGlobal, Float)] = []
    private(set) var appliedResolutions: [Bool] = []
    private(set) var contextCrosshairs: [ReferenceKey?] = []
    var slots: [String] = []
    var saveError: Error?
    private(set) var slotListings = 0

    var residentReferenceCount: Int {
        entries.count
    }

    func referenceEntry(formID: FormID) -> RuntimeReferenceEntry? {
        entries.first { $0.formID == formID }
    }

    func setTimeOfDay(_ hour: Float) {
        timeOfDayWrites.append(hour)
    }

    func persistTimeOfDay(_ hour: Float) {
        persistedHours.append(hour)
    }

    func projectTimeGlobal(_ global: GameClock.TimeGlobal, value: Float) -> Float? {
        projectedGlobals.append((global, value))
        guard var clock = gameClock else { return nil }
        let previous = clock.projectedValue(global)
        clock.setProjectedValue(value, for: global)
        gameClock = clock
        return previous
    }

    func applyGlobalResolution(_ resolution: GlobalResolution, reroll: Bool) {
        appliedResolutions.append(reroll)
    }

    func conditionContext(
        crosshair: RuntimeReferenceEntry?, globals: GlobalResolution
    ) -> ConditionContext {
        contextCrosshairs.append(crosshair?.key)
        return ConditionContext(globals: globals)
    }

    func saveSlots() throws -> [String] {
        slotListings += 1
        return slots
    }

    func saveSession(slot: String) throws {
        if let saveError {
            throw saveError
        }
        slots.append(slot)
    }

    func loadSession(slot: String) throws {
        guard slots.contains(slot) else { throw FakeSaveError.unwritable }
    }

    static func referenceEntry(objectID: UInt32) throws -> RuntimeReferenceEntry {
        var base = Data()
        base.appendUInt32(0x700)
        let reference = try PlacedReference(record: ESMFixture.parseRecord(ESMFixture.record(
            "REFR",
            formID: objectID,
            data: ESMFixture.field("NAME", base) + ESMFixture.field("DATA", Data(count: 24))
        )))
        return RuntimeReferenceEntry(
            key: .plugin(name: "test.esm", objectID: objectID),
            formID: FormID(objectID),
            isPersistent: false,
            record: .reference(reference)
        )
    }
}
