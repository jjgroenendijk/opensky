// The Runtime State coordinator's world reads, journal tail, clock scrubs, and
// save outcomes, over a fake world. Synthetic GLOB records and references.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import Testing

@MainActor
struct RuntimeStateCoordinatorTests {
    private let store = WorldStateStore()
    private let world = FakeRuntimeStateWorld()
    private let coordinator: RuntimeStateCoordinator

    init() {
        coordinator = RuntimeStateCoordinator(store: store)
        coordinator.attach(world: world)
    }

    /// Reference and global writes share one sequence counter, so the merged
    /// tail is in the order the session wrote them.
    @Test func journalTailInterleavesReferenceAndGlobalWritesBySequence() throws {
        try coordinator.attach(globals: Self.globals())
        store.set(ReferenceEnableState(isEnabled: false), for: Self.referenceKey)
        coordinator.setGlobalValue(120, editorID: "TimeScale")
        store.set(ReferenceEnableState(isEnabled: true), for: Self.referenceKey)
        coordinator.resetGlobalValue(editorID: "TimeScale")

        let snapshot = coordinator.runtimeStateSnapshot
        #expect(snapshot.journalTail == [
            "1 set enableState test.esm:00003F",
            "2 set global TimeScale = 120",
            "3 set enableState test.esm:00003F",
            "4 reset global TimeScale"
        ])
        #expect(snapshot.overriddenGlobalCount == 0)
        #expect(snapshot.nextJournalSequence == 5)
    }

    @Test func snapshotReportsTheOverriddenGlobalCount() throws {
        try coordinator.attach(globals: Self.globals())
        #expect(coordinator.runtimeStateSnapshot.overriddenGlobalCount == 0)
        coordinator.setGlobalValue(120, editorID: "TimeScale")
        #expect(coordinator.runtimeStateSnapshot.overriddenGlobalCount == 1)
        coordinator.resetAllGlobalOverrides()
        #expect(coordinator.runtimeStateSnapshot.overriddenGlobalCount == 0)
    }

    /// The cap applies to the merged log, not to either ring alone.
    @Test func mergedTailIsCappedAtTheSnapshotLimit() throws {
        try coordinator.attach(globals: Self.globals())
        for step in 1 ... 6 {
            store.set(
                ReferenceEnableState(isEnabled: step.isMultiple(of: 2)),
                for: Self.referenceKey
            )
            coordinator.setGlobalValue(Float(step), editorID: "TimeScale")
        }
        let tail = coordinator.runtimeStateSnapshot.journalTail
        #expect(tail.count == RuntimeStateSnapshot.journalTailLimit)
        #expect(tail.first == "5 set enableState test.esm:00003F")
        #expect(tail.last == "12 set global TimeScale = 6")
    }

    /// A short global rounds onto its type, and the line shows the stored value.
    @Test func globalJournalLineShowsTheCoercedValue() throws {
        try coordinator.attach(globals: Self.globals())
        coordinator.setGlobalValue(3.7, editorID: "TimeScale")
        #expect(coordinator.runtimeStateSnapshot.journalTail == ["1 set global TimeScale = 4"])
    }

    @Test func crosshairResolvesThroughTheResidentIndex() throws {
        let entry = try FakeRuntimeStateWorld.referenceEntry(objectID: 0x3F)
        world.entries = [entry]
        world.crosshairReference = entry.formID
        #expect(coordinator.runtimeStateSnapshot.currentTargetDescription == "test.esm:00003F")
        #expect(coordinator.setReferenceEnabled(false, target: .currentTarget))
        #expect(coordinator.setReferenceEnabled(true, target: .formID("0x3f")))
        #expect(!coordinator.setReferenceEnabled(true, target: .formID("0x40")))
    }

    /// A FormID that is not resident still shows as itself.
    @Test func unresolvedCrosshairShowsTheBareFormID() {
        world.crosshairReference = FormID(0x40)
        #expect(coordinator.runtimeStateSnapshot.currentTargetDescription == FormID(0x40)
            .description)
        #expect(!coordinator.resetReferenceState(target: .currentTarget))
    }

    @Test func nudgesAccumulateFromTheResolvedTransform() throws {
        let entry = try FakeRuntimeStateWorld.referenceEntry(objectID: 0x3F)
        world.entries = [entry]
        coordinator.nudgeReferenceTransform(target: .formID("3F"))
        coordinator.nudgeReferenceTransform(target: .formID("3F"))
        let moved = store.component(ReferenceTransformOverride.self, for: entry.key)
        #expect(moved?.position == RuntimeStateTuning.transformNudge * 2)
    }

    /// With plugins and a clock, an hour scrub writes `GameHour`, so it is
    /// journalled and redirected into the clock.
    @Test func hourScrubGoesThroughTheTimeGlobal() throws {
        world.gameClock = GameClock()
        try coordinator.attach(globals: Self.globals())
        coordinator.setGameClockHour(6)
        #expect(world.projectedGlobals.map(\.0) == [.gameHour])
        #expect(world.timeOfDayWrites.isEmpty)
        #expect(world.persistedHours == [6])
        #expect(store.globalJournalEntries.count == 1)
    }

    @Test func hourScrubWithoutGlobalsMovesTheRendererDirectly() {
        world.gameClock = GameClock()
        coordinator.setGameClockHour(6)
        #expect(world.timeOfDayWrites == [6])
        #expect(world.persistedHours == [6])
    }

    @Test func dateScrubWithoutGlobalsWritesTheClock() {
        world.gameClock = GameClock()
        coordinator.setGameClockDate(day: 30, month: 1, year: 202)
        #expect(world.gameClock?.projectedValue(.gameYear) == 202)
        #expect(world.gameClock?.projectedValue(.gameMonth) == 1)
    }

    @Test func attachingGlobalsSeedsTheRendererAndRerollsOnWrites() throws {
        try coordinator.attach(globals: Self.globals())
        coordinator.setGlobalValue(30, editorID: "TimeScale")
        #expect(world.appliedResolutions == [false, true])
    }

    @Test func saveOutcomesAndSlotCache() async {
        #expect(coordinator.runtimeStateSaveSlots.isEmpty)
        #expect(coordinator.runtimeStateSaveSlots.isEmpty)
        await coordinator.slotListing?.value
        #expect(world.slotListings == 1)

        coordinator.saveWorldState(slot: "quick")
        #expect(coordinator.lastSaveOutcome == .running(operation: "save", slot: "quick"))
        coordinator.loadWorldState(slot: "quick")
        #expect(coordinator.lastSaveOutcome == .failed(
            operation: "load", message: "another save or load is running"
        ))
        await coordinator.saveWork?.value
        #expect(coordinator.lastSaveOutcome == .saved(slot: "quick"))
        _ = coordinator.runtimeStateSaveSlots
        await coordinator.slotListing?.value
        #expect(coordinator.runtimeStateSaveSlots == ["quick"])

        coordinator.loadWorldState(slot: "quick")
        await coordinator.saveWork?.value
        #expect(coordinator.lastSaveOutcome == .loaded(slot: "quick"))

        world.saveError = FakeSaveError.unwritable
        coordinator.saveWorldState(slot: "other")
        await coordinator.saveWork?.value
        #expect(coordinator.lastSaveOutcome == .failed(operation: "save", message: "unwritable"))
    }

    @Test func conditionsWithoutMusicRecordsAreUnavailable() {
        let report = coordinator.evaluateConditions(source: "MUSDungeon")
        #expect(report == .unavailable(
            source: "MUSDungeon",
            message: "No music records are loaded, so no condition list can be evaluated."
        ))
        #expect(coordinator.runtimeStateConditionSources.isEmpty)
    }

    @Test func conditionContextNamesTheCrosshair() throws {
        let entry = try FakeRuntimeStateWorld.referenceEntry(objectID: 0x3F)
        world.entries = [entry]
        world.crosshairReference = entry.formID
        _ = coordinator.conditionContext()
        #expect(world.contextCrosshairs == [entry.key])
    }

    private static let referenceKey = ReferenceKey.plugin(name: "test.esm", objectID: 0x3F)

    private static func globals() throws -> GlobalStore {
        try GlobalFixture.store(
            GlobalFixture.record(formID: 0x3A, editorID: "TimeScale", type: .short, value: 20)
                + GlobalFixture.record(formID: 0x38, editorID: "GameHour", type: .float, value: 8)
        )
    }
}
