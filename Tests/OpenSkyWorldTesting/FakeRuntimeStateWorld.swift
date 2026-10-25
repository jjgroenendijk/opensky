// Plain-value fake for `RuntimeStateCoordinatorTests`: one optional resident
// reference, an optional clock, and a save store held in memory.

import Foundation
@testable import OpenSkyAudio
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyRuntimeState
import OpenSkyWorldConditions
@testable import OpenSkyWorldState

public enum FakeSaveError: Error {
    case unwritable
}

public final class FakeRuntimeStateWorld: RuntimeStateWorld {
    public var entries: [RuntimeReferenceEntry] = []
    public var crosshairReference: FormID?
    public var gameClock: GameClock?
    public var timescale: Float?
    public var musicStore: MusicRecordStore?
    public var globalStore: GlobalStore?
    public private(set) var timeOfDayWrites: [Float] = []
    public private(set) var persistedHours: [Float] = []
    public private(set) var projectedGlobals: [(GameClock.TimeGlobal, Float)] = []
    public private(set) var appliedResolutions: [Bool] = []
    public private(set) var contextCrosshairs: [ReferenceKey?] = []
    public var slots: [String] = []
    public var saveError: Error?
    public private(set) var slotListings = 0

    public init() {}

    public func referenceEntry(formID: FormID) -> RuntimeReferenceEntry? {
        entries.first { $0.formID == formID }
    }

    public func setTimeOfDay(_ hour: Float) {
        timeOfDayWrites.append(hour)
    }

    public func persistTimeOfDay(_ hour: Float) {
        persistedHours.append(hour)
    }

    public func projectTimeGlobal(_ global: GameClock.TimeGlobal, value: Float) -> Float? {
        projectedGlobals.append((global, value))
        guard var clock = gameClock else { return nil }
        let previous = clock.projectedValue(global)
        clock.setProjectedValue(value, for: global)
        gameClock = clock
        return previous
    }

    public func applyGlobalResolution(_ resolution: GlobalResolution, reroll: Bool) {
        appliedResolutions.append(reroll)
    }

    public func conditionContext(
        crosshair: RuntimeReferenceEntry?, globals: GlobalResolution, indexing _: [ReferenceKey]
    ) -> ConditionContext {
        contextCrosshairs.append(crosshair?.key)
        return ConditionContext(globals: globals)
    }

    public func saveSlots() async throws -> [String] {
        slotListings += 1
        return slots
    }

    public func saveSession(slot: String) async throws {
        if let saveError {
            throw saveError
        }
        slots.append(slot)
    }

    public func loadSession(slot: String) async throws {
        guard slots.contains(slot) else { throw FakeSaveError.unwritable }
    }

    public static func referenceEntry(objectID: UInt32) throws -> RuntimeReferenceEntry {
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
