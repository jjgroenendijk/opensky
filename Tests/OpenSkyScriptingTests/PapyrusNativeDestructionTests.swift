// The destruction rule and natives over a synthetic lever whose base (0x100) carries
// `DEST` data: 100 health, stage 1 at 50 percent, stage 2 at 0 percent that destroys.

import Foundation
import OpenSkyCombatInterface
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNativeDestructionTests {
    private typealias Fixture = PapyrusNativeReferenceFixture

    private static func stage(percent: UInt8, index: UInt8, flags: UInt8) -> Data {
        var bytes = Data([percent, index, 0, flags])
        bytes.append(Data(count: 16))
        return ESMFixture.field("DSTD", bytes) + ESMFixture.field("DSTF", Data())
    }

    private static let destructibleFields: Data = {
        var header = Data()
        header.appendUInt32(100)
        header.append(contentsOf: [2, 0, 0, 0])
        return ESMFixture.field("DEST", header)
            + stage(percent: 50, index: 1, flags: 0)
            + stage(percent: 0, index: 2, flags: DestructionProgress.destroy)
    }()

    private static func store() throws -> KeywordStore {
        let file = try ESMFile(data: ESMFixture.tes4() + ESMFixture.topGroup(
            "ACTI", contents: ESMFixture.record("ACTI", formID: 0x100, data: destructibleFields)
        ))
        return KeywordStore(index: RecordIndex(
            plugins: [(PapyrusWorldFixture.pluginName, file)], recordTypes: ["ACTI"]
        ))
    }

    private static func data() throws -> Destructible {
        let store = try store()
        let id = try #require(store.resolvedID(
            FormID(0x100), fromPlugin: PapyrusWorldFixture.pluginName
        ))
        return try #require(store.destructible(of: id))
    }

    @Test func damagePassesTheStagesAndTheLastDestroys() throws {
        let data = try Self.data()
        var progress = DestructionProgress()
        let disables = progress.apply(damage: 40, to: data)
        #expect(!disables)
        #expect(progress.stage == 0)
        _ = progress.apply(damage: 20, to: data)
        #expect(progress.stage == 1 && !progress.isDestroyed)
        _ = progress.apply(damage: 50, to: data)
        #expect(progress.stage == 2 && progress.isDestroyed)
    }

    @Test func aCapStageHoldsHealthAtItsPercent() throws {
        var capped = try Self.data()
        capped.stages[0].flags = DestructionProgress.capDamage
        var progress = DestructionProgress()
        _ = progress.apply(damage: 500, to: capped)
        #expect(progress.stage == 1 && progress.damage == 50 && !progress.isDestroyed)
    }

    private static func fixture() throws -> Fixture {
        let fixture = try Fixture.make(events: [
            ("OnDestructionStageChanged", PapyrusWorldFixture.probeBody(note: "stage"))
        ])
        fixture.session.bridge.keywordStore = try store()
        return fixture
    }

    @Test func theNativesStoreTheStageAndSendTheEvent() throws {
        let fixture = try Self.fixture()
        #expect(fixture.call("DamageObject", arguments: [.float(60)]) == .returned(.none))
        #expect(fixture.call("GetCurrentDestructionStage", returnType: .integer)
            == .returned(.integer(1)))
        PapyrusWorldFixture.drain(fixture.session.world)
        #expect(fixture.session.dispatch.notes == ["stage"])
        #expect(fixture.call("SetDestroyed") == .returned(.none))
        let state = fixture.session.bridge.scriptedState(of: fixture.key)
        #expect(state.flag(ScriptedStateName.destroyed) == true)
        #expect(fixture.call("ClearDestruction") == .returned(.none))
        #expect(fixture.session.bridge.scriptedState(of: fixture.key).isEmpty)
    }

    @Test func hitsAndKillsAreRecordedForTheConditions() throws {
        let fixture = try Fixture.make()
        let bridge = fixture.session.bridge
        let hit = ScriptHitEvent(target: fixture.key, aggressor: .player)
        bridge.recordHit(hit, targetWasHostile: false)
        bridge.recordHit(hit, targetWasHostile: true)
        #expect(bridge.scriptedState(of: fixture.key).value(ScriptedStateName.friendHits) == 1)
        bridge.recordHit(
            ScriptHitEvent(target: .player, aggressor: fixture.key),
            targetWasHostile: true
        )
        #expect(bridge.scriptedState(of: .player).form(ScriptedStateName.lastHostileActor)
            == fixture.key)
        bridge.recordKill(victim: fixture.key, killer: .player)
        #expect(bridge.scriptedState(of: fixture.key).form(ScriptedStateName.killer) == .player)
    }
}
