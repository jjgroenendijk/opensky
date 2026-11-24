// An owner unlocks or locks the doors it owns and opens or closes the cells behind them
// to the player. See docs/engine/crime.md#owners-lock-and-unlock.

import Foundation
@testable import OpenSkyAIAdapters
@testable import OpenSkyAIPackages
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import OpenSkyWorldTesting
import Testing

@MainActor
struct AIOwnerDoorTests {
    private let host = AIHost()
    private let adapter: AIWorldAdapter
    private let bridge = FakePapyrusWorldStateBridgePort()
    private static let ownerBase: UInt32 = 0x710
    private static let owner = PackageRuntimeFixture.key(0x711)
    private static let cell = ReferenceKey.generated(7)

    init() throws {
        adapter = AIWorldAdapter(game: host, stage: nil)
        host.fakeScripts.bridge = bridge
        let door = try Self.door(0x950, owner: Self.ownerBase, leadsTo: 0x951)
        host.fakeStreamer.residents.residentReferenceIndexResult =
            RuntimeReferenceIndex(entries: [door])
        host.fakeStreamer.referenceEntryKeyResult = try PackageRuntimeFixture.residentActor(
            0x711, base: Self.ownerBase
        )
        host.fakeStreamer.cellLocationResult = .interior(FormID(0x900))
        bridge.referenceKeyResult = Self.cell
        bridge.lockStateResult = ReferenceLockState(isLocked: true, level: 0, key: nil)
    }

    private func start(flags: Package.GeneralFlags) throws {
        try adapter.worlds.packageProcedure(PackageScriptEvent(
            kind: .begin, actor: Self.owner,
            package: PackageRuntimeFixture.package(id: 0x800, flags: flags)
        ))
    }

    @Test func theStartFlagUnlocksTheOwnersDoorAndOpensItsCell() throws {
        try start(flags: .unlockDoorsAtStart)
        #expect(bridge.writeCalls.count == 1)
        #expect(bridge.updateScriptedStateCalls == [Self.cell])
    }

    @Test func aPackageWithoutTheFlagLeavesTheDoorsAlone() throws {
        try start(flags: [])
        #expect(bridge.writeCalls.isEmpty)
        #expect(bridge.updateScriptedStateCalls.isEmpty)
    }

    @Test func anOwnerInNoCellUnlocksNothing() throws {
        host.fakeStreamer.cellLocationResult = nil
        try start(flags: .unlockDoorsAtStart)
        #expect(bridge.writeCalls.isEmpty)
    }

    @Test func anOwnerOutdoorsUnlocksTheDoorsNearIt() throws {
        host.fakeStreamer.cellLocationResult = .exterior(CellCoordinate(x: 0, y: 0))
        try start(flags: .unlockDoorsAtStart)
        #expect(bridge.writeCalls.count == 1)
    }

    /// The procedure's radius does not limit it: a door far from the place still locks.
    @Test func theLockProcedureReachesEveryOwnedDoorOfTheCell() {
        bridge.lockStateResult = ReferenceLockState(isLocked: false, level: 0, key: nil)
        let far = SIMD3<Float>(9000, 0, 0)
        let result = adapter.worlds.packageAction(
            .setDoorsLocked(true, center: far, radius: 200), actor: Self.owner
        )
        #expect(result == .done)
        #expect(bridge.writeCalls.count == 1)
        #expect(bridge.updateScriptedStateCalls == [Self.cell])
    }

    @Test func aProcedurePlaceOutdoorsLocksNothing() {
        host.fakeStreamer.cellLocationResult = .exterior(CellCoordinate(x: 0, y: 0))
        bridge.lockStateResult = ReferenceLockState(isLocked: false, level: 0, key: nil)
        let result = adapter.worlds.packageAction(
            .setDoorsLocked(true, center: .zero, radius: 200), actor: Self.owner
        )
        #expect(result == .done)
        #expect(bridge.writeCalls.isEmpty)
    }

    @Test func aDoorOfAnotherOwnerStaysLocked() throws {
        let door = try Self.door(0x952, owner: 0x999, leadsTo: 0x953)
        host.fakeStreamer.residents.residentReferenceIndexResult =
            RuntimeReferenceIndex(entries: [door])
        try start(flags: .unlockDoorsAtStart)
        #expect(bridge.writeCalls.isEmpty)
    }

    /// A load door owned by `owner` at the origin, which the fixture actor stands on.
    private static func door(
        _ objectID: UInt32, owner: UInt32, leadsTo partner: UInt32
    ) throws -> RuntimeReferenceEntry {
        let reference = try PlacedReference(record: ESMFixture.parseRecord(ESMFixture.record(
            "REFR", formID: objectID,
            data: PackageRuntimeFixture.formIDField("NAME", 0x700)
                + ESMFixture.field("DATA", Data(count: 24))
                + ESMFixture.field(
                    "XTEL",
                    PackageRuntimeFixture.formIDData(partner)
                        + Data(count: 28)
                )
                + PackageRuntimeFixture.formIDField("XOWN", owner)
        )))
        return RuntimeReferenceEntry(
            key: PackageRuntimeFixture.key(objectID), formID: FormID(objectID),
            isPersistent: false, record: .reference(reference)
        )
    }
}
