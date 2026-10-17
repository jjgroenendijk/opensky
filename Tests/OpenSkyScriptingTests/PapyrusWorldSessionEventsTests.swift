// Events the engine sends when a cell detaches, a save loads, and the player changes
// location. Every script is built in code.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsPEX
import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusWorldSessionEventsTests {
    private typealias Fixture = PapyrusWorldFixture

    private static func world(
        _ probe: PapyrusWorldProbeDispatch, events: [String]
    ) -> PapyrusWorldRuntime {
        let script = Fixture.eventScript("AScript", events: events.map {
            ($0, Fixture.probeBody(note: $0.lowercased()))
        })
        return Fixture.worldRuntime(objects: [script], nativeDispatch: probe)
    }

    private static func attach(
        _ world: PapyrusWorldRuntime, key: ReferenceKey? = nil
    ) throws {
        let entry = try Fixture.referenceEntry(
            objectID: 1,
            scripts: [.init("AScript", properties: [])]
        )
        let placed = RuntimeReferenceEntry(
            key: key ?? entry.key, formID: entry.formID, isPersistent: key != nil,
            record: entry.record
        )
        world.attach(
            cell: Fixture.cell, references: Fixture.index([placed]),
            formIDResolver: Fixture.resolver, firstIntegration: true
        )
    }

    @Test func detachSendsUnloadThenCellDetachBeforeRetiring() throws {
        let probe = PapyrusWorldProbeDispatch()
        let world = Self.world(probe, events: ["OnUnload", "OnCellDetach"])
        try Self.attach(world)
        Fixture.drain(world)
        world.detach(cell: Fixture.cell)
        #expect(world.instancesByKey.count == 1)
        Fixture.drain(world)
        #expect(probe.notes == ["onunload", "oncelldetach"])
        #expect(world.instancesByKey.isEmpty)
        #expect(world.retiringKeys.isEmpty)
    }

    @Test func reattachKeepsAnInstanceThatWaitedToRetire() throws {
        let probe = PapyrusWorldProbeDispatch()
        let world = Self.world(probe, events: ["OnCellDetach"])
        try Self.attach(world)
        Fixture.drain(world)
        world.detach(cell: Fixture.cell)
        try Self.attach(world)
        Fixture.drain(world)
        #expect(world.instancesByKey.count == 1)
        #expect(world.retiringKeys.isEmpty)
    }

    @Test func detachRetiresAnInstanceWithoutHandlersAtOnce() throws {
        let world = Self.world(PapyrusWorldProbeDispatch(), events: ["OnLoad"])
        try Self.attach(world)
        world.detach(cell: Fixture.cell)
        #expect(world.instancesByKey.isEmpty)
    }

    @Test func playerScriptsHearLoadGameAndLocationChanges() throws {
        let probe = PapyrusWorldProbeDispatch()
        let world = Self.world(probe, events: ["OnPlayerLoadGame", "OnLocationChange"])
        try Self.attach(world, key: .player)
        Fixture.drain(world)
        let fake = FakePlayerWorld()
        let coordinator = ScriptCoordinator(world: fake)
        coordinator.install(runtime: world, bridge: nil)

        coordinator.restore(instances: [], timers: [])
        fake.playerLocation = .some(nil)
        coordinator.advance(delta: 0)
        Fixture.drain(world)
        #expect(probe.notes == ["onplayerloadgame"])

        // A cell that is not resident yet is not a move.
        fake.playerLocation = nil
        coordinator.advance(delta: 0)
        fake.playerLocation = .some(ResolvedFormID(plugin: Fixture.pluginName, objectID: 0x20))
        coordinator.advance(delta: 0)
        coordinator.advance(delta: 0)
        Fixture.drain(world)
        #expect(probe.notes == ["onplayerloadgame", "onlocationchange"])
    }

    @Test func actorScriptsHearFurnitureSpellsAndFastTravel() throws {
        let probe = PapyrusWorldProbeDispatch()
        let world = Self.world(
            probe, events: ["OnSit", "OnGetUp", "OnSpellCast", "OnPlayerFastTravelEnd"]
        )
        try Self.attach(world, key: .player)
        Fixture.drain(world)
        let chair = ReferenceKey.plugin(name: Fixture.pluginName, objectID: 0x30)

        #expect(world.queueFurnitureEvent(sitting: true, actor: .player, furniture: chair) == 1)
        #expect(world.queueFurnitureEvent(sitting: false, actor: .player, furniture: chair) == 1)
        #expect(world.queueSpellCast(chair, by: .player) == 1)
        #expect(world.queuePlayerFastTravelEnd(gameHours: 2.5) == 1)
        #expect(world.queueFurnitureEvent(sitting: true, actor: chair, furniture: chair) == 0)
        Fixture.drain(world)
        #expect(probe.notes == ["onsit", "ongetup", "onspellcast", "onplayerfasttravelend"])
    }
}

private final class FakePlayerWorld: ScriptWorld {
    var crosshairReference: FormID?
    var gameClock: GameClock?
    var playerLocation: ResolvedFormID??

    func referenceKey(formID _: FormID) -> ReferenceKey? {
        nil
    }
}
