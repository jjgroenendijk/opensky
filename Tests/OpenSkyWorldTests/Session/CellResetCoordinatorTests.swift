// Cell reset (CK wiki "Cell Reset"): a cell the player left long enough ago returns to
// its plugin state on the next visit, apart from what the wiki lists as kept.

import Foundation
@testable import OpenSkyCells
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyInventoryInterface
@testable import OpenSkyRendering
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import Testing

@MainActor
struct CellResetCoordinatorTests {
    private static let cell = CellSceneLocation.interior(FormID(0x0001_6000))
    private let store = WorldStateStore()

    private func coordinator(
        queries: CellResetQueries = CellResetQueries(), hours: @escaping () -> Double
    ) -> CellResetCoordinator {
        CellResetCoordinator(store: store, queries: queries) {
            GameClock(totalGameSeconds: hours() * GameClock.secondsPerHour)
        }
    }

    @Test func aCellLeftLongEnoughResetsItsReferences() throws {
        var now = 1000.0
        let reset = coordinator { now }
        let scene = try Self.scene([Self.reference(0x10), Self.reference(0x11, noRespawn: true)])
        store.set(ReferenceDeletionState.deleted, for: Self.key(0x10), in: Self.cell)
        store.set(ReferenceDeletionState.deleted, for: Self.key(0x11), in: Self.cell)
        store.set(ReferenceEnableState.disabled, for: Self.key(0x10), in: Self.cell)
        reset.cellDetached(Self.cell)
        now += 240
        #expect(reset.cellAttached(scene) == [Self.key(0x10)])
        #expect(store.component(ReferenceDeletionState.self, for: Self.key(0x10)) == nil)
        // The enable state and a No Respawn reference are kept.
        #expect(store.component(ReferenceEnableState.self, for: Self.key(0x10)) == .disabled)
        #expect(store.component(ReferenceDeletionState.self, for: Self.key(0x11)) == .deleted)
        #expect(reset.ledger.departures.isEmpty)
    }

    @Test func aShortAbsenceResetsNothing() throws {
        var now = 1000.0
        let reset = coordinator { now }
        let scene = try Self.scene([Self.reference(0x10)])
        store.set(ReferenceDeletionState.deleted, for: Self.key(0x10), in: Self.cell)
        reset.cellDetached(Self.cell)
        now += 239
        #expect(reset.cellAttached(scene).isEmpty)
        #expect(store.component(ReferenceDeletionState.self, for: Self.key(0x10)) == .deleted)
        // The departure is used up, so the next visit counts from the next exit.
        #expect(reset.ledger.departures.isEmpty)
    }

    @Test func aClearedLocationWaitsTheLongerTime() throws {
        var now = 1000.0
        var queries = CellResetQueries()
        queries.isCleared = { _ in true }
        let reset = coordinator(queries: queries) { now }
        let scene = try Self.scene([Self.reference(0x10)])
        store.set(ReferenceDeletionState.deleted, for: Self.key(0x10), in: Self.cell)
        reset.cellDetached(Self.cell)
        now += 300
        #expect(reset.cellAttached(scene).isEmpty)
        reset.cellDetached(Self.cell)
        now += 720
        #expect(reset.cellAttached(scene) == [Self.key(0x10)])
    }

    /// `Cell.Reset` resets on the next load even in a never-resets zone, and leaving the
    /// cell before that load keeps the flag.
    @Test func aScriptedResetWinsOverTheZoneAndTheClock() throws {
        var now = 1000.0
        var queries = CellResetQueries()
        queries.neverResets = { _ in true }
        let reset = coordinator(queries: queries) { now }
        let scene = try Self.scene([Self.reference(0x10)])
        store.set(ReferenceDeletionState.deleted, for: Self.key(0x10), in: Self.cell)
        reset.flagForReset(Self.cell)
        now += 1
        reset.cellDetached(Self.cell)
        #expect(reset.cellAttached(scene) == [Self.key(0x10)])
        #expect(reset.ledger.departures.isEmpty)
    }

    @Test func aNeverResetsZoneAndANonRespawningBaseKeepTheirState() throws {
        var now = 1000.0
        var neverResets = true
        var queries = CellResetQueries()
        queries.neverResets = { _ in neverResets }
        queries.respawns = { _ in neverResets }
        let reset = coordinator(queries: queries) { now }
        let scene = try Self.scene([Self.reference(0x10)])
        store.set(ReferenceDeletionState.deleted, for: Self.key(0x10), in: Self.cell)
        reset.cellDetached(Self.cell)
        now += 1000
        #expect(reset.cellAttached(scene).isEmpty)
        neverResets = false
        reset.cellDetached(Self.cell)
        now += 1000
        #expect(reset.cellAttached(scene).isEmpty)
        #expect(store.component(ReferenceDeletionState.self, for: Self.key(0x10)) == .deleted)
    }

    @Test func makingResetsDueResetsOnTheNextVisit() throws {
        let reset = coordinator { 1000 }
        let scene = try Self.scene([Self.reference(0x10)])
        store.set(ReferenceDeletionState.deleted, for: Self.key(0x10), in: Self.cell)
        reset.cellDetached(Self.cell)
        #expect(reset.makeAllDue() == 1)
        #expect(reset.cellAttached(scene) == [Self.key(0x10)])
        #expect(reset.readout.contains("1 references"))
    }

    @Test func aResetRegrowsAPlantAndClearsTemperedCopies() throws {
        var now = 1000.0
        let reset = coordinator { now }
        let scene = try Self.scene([Self.reference(0x10)])
        store.set(ReferenceHarvestState.harvested, for: Self.key(0x10), in: Self.cell)
        store.set(ItemCopyState(levels: [0x100: [10]]), for: Self.key(0x10), in: Self.cell)
        reset.cellDetached(Self.cell)
        now += 240
        #expect(reset.cellAttached(scene) == [Self.key(0x10)])
        #expect(store.component(ReferenceHarvestState.self, for: Self.key(0x10)) == nil)
        #expect(store.component(ItemCopyState.self, for: Self.key(0x10)) == nil)
    }

    // MARK: - Fixtures

    /// A leveled roll freezes its level once, and a reset clears it so the next attach
    /// freezes the level of that moment (docs/engine/leveled-lists.md).
    @Test func aLeveledRollStaysFrozenUntilTheCellResets() throws {
        var now = 1000.0
        let reset = coordinator { now }
        let scene = try Self.scene([Self.reference(0x10), Self.reference(0x11)])
        let rolls: (RuntimeReferenceEntry) -> Bool = { $0.key == Self.key(0x10) }
        #expect(LeveledRollFreeze
            .freeze(scene, level: 4, in: store, rolls: rolls) == [Self.key(0x10)])
        #expect(LeveledRollFreeze.freeze(scene, level: 9, in: store, rolls: rolls).isEmpty)
        #expect(store.frozenLeveledLevel(of: Self.key(0x10)) == 4)
        #expect(store.frozenLeveledLevel(of: Self.key(0x11)) == nil)
        reset.cellDetached(Self.cell)
        now += 240
        #expect(reset.cellAttached(scene) == [Self.key(0x10)])
        #expect(LeveledRollFreeze
            .freeze(scene, level: 9, in: store, rolls: rolls) == [Self.key(0x10)])
        #expect(store.frozenLeveledLevel(of: Self.key(0x10)) == 9)
    }

    private static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: objectID)
    }

    private static func reference(
        _ objectID: UInt32, noRespawn: Bool = false
    ) throws -> RuntimeReferenceEntry {
        var name = Data()
        name.appendUInt32(0x100)
        let bytes = ESMFixture.record(
            "REFR",
            formID: objectID,
            flags: noRespawn ? 0x4000_0000 : 0,
            data: ESMFixture.field("NAME", name) + ESMFixture.field("DATA", Data(count: 24))
        )
        let reference = try PlacedReference(record: ESMFixture.parseRecord(bytes))
        return RuntimeReferenceEntry(
            key: key(objectID), formID: FormID(objectID), isPersistent: false,
            record: .reference(reference)
        )
    }

    private static func scene(_ entries: [RuntimeReferenceEntry]) -> CellScene {
        CellScene(
            renderScene: RenderScene(instances: []),
            summary: CellLoadSummary(
                cellName: "test", gridX: 0, gridY: 0,
                totalRefCount: 0, drawnRefCount: 0,
                unsupportedBaseSkipCount: 0, markerSkipCount: 0,
                modelFailureSkipCount: 0, malformedRefSkipCount: 0,
                modelCount: 0, textureCount: 0, missingTextureCount: 0
            ),
            bounds: nil,
            location: cell,
            references: RuntimeReferenceIndex(entries: entries)
        )
    }
}
