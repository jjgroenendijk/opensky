// A passed destruction stage swaps the model, throws debris, sets off its explosion,
// and keeps damaging the object each second while health is left.

import Foundation
@testable import OpenSkyCombatAdapters
import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyScriptingInterface
import OpenSkySessionTesting
@testable import OpenSkyWorldState
import Testing

@MainActor
struct EffectsDestructionStageTests {
    private let host = CombatHost()
    private let bridge = FakePapyrusWorldStateBridgePort()

    private static let barrel = ReferenceKey.plugin(name: "base.esm", objectID: 0x50)
    private static let blast = ReferenceKey.plugin(name: "base.esm", objectID: 0x60)
    private static let shards = ReferenceKey.plugin(name: "base.esm", objectID: 0x61)

    init() {
        host.fakeScripts.bridge = bridge
    }

    private static func placedState() throws -> ReferenceState {
        var name = Data()
        name.appendUInt32(0x70)
        let fields = ESMFixture.field("NAME", name) + ESMFixture.field("DATA", Data(count: 24))
        let actor = try PlacedActor(record: ESMFixture.parseRecord(
            ESMFixture.record("ACHR", formID: 0x50, data: fields)
        ))
        return ReferenceState(baseline: RuntimeReferenceEntry(
            key: barrel, formID: FormID(0x50), isPersistent: true, record: .actor(actor)
        ))
    }

    @Test func noScriptBridgeDoesNothing() {
        host.fakeScripts.bridge = nil
        var burns = DestructionBurns()
        EffectsDestructionAdapter(game: host).step(1, burns: &burns)
        #expect(burns.perSecond.isEmpty)
    }

    @Test func aStageSwapsTheModelThrowsDebrisAndSetsOffItsBlast() throws {
        let explosions = host.fakeCombat.explosions
        explosions.specForResult = ExplosionSpec(name: "Blast", damage: 10, radius: 100)
        explosions.detonateResult = ExplosionReport(
            name: "Blast", cause: .script, position: .zero, damaged: [:], soundsPlayed: 0,
            imageSpaceStrength: nil, hazardPlaced: false, debrisThrown: 0
        )
        bridge.referenceStateResult = try Self.placedState()
        bridge.takeDestructionChangesResult = [DestructionStageChange(
            reference: Self.barrel,
            stages: [
                .init(index: 1, model: "barrel01.nif", debris: Self.shards, debrisCount: 3),
                .init(index: 2, selfDamagePerSecond: 4, explosion: Self.blast)
            ]
        )]
        var burns = DestructionBurns()
        EffectsDestructionAdapter(game: host).step(0, burns: &burns)
        let model = host.fakeWorldState.setCalls.first?.component as? ReferenceDamageModel
        #expect(model == ReferenceDamageModel(path: "barrel01.nif", stage: 0))
        #expect(explosions.throwDebrisCalls.count == 1)
        #expect(explosions.detonateCalls.count == 1)
        #expect(burns.perSecond == [Self.barrel: 4])
    }

    @Test func aBurningObjectTakesDamageEachSecondUntilItsHealthIsGone() {
        var burns = DestructionBurns()
        burns.perSecond[Self.barrel] = 4
        let adapter = EffectsDestructionAdapter(game: host)
        bridge.destructionHealthLeftResult = 10
        adapter.step(0.5, burns: &burns)
        #expect(bridge.damageDestructibleCalls.isEmpty)
        adapter.step(0.6, burns: &burns)
        #expect(bridge.damageDestructibleCalls.count == 1)
        bridge.destructionHealthLeftResult = 0
        adapter.step(1, burns: &burns)
        #expect(bridge.damageDestructibleCalls.count == 1)
        #expect(burns.perSecond.isEmpty)
    }
}
