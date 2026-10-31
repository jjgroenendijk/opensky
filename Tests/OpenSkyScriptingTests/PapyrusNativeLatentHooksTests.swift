// The natives the app answers through hooks: sound instances, shader particles,
// scripted pathing, the ash pile, and eye textures, over a synthetic lever.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusNativeLatentHooksTests {
    private typealias Fixture = PapyrusNativeReferenceFixture

    private func call(
        _ fixture: Fixture, _ script: String, _ name: String,
        _ arguments: [PapyrusValue] = [], returnType: PapyrusType = .none
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            script, name, receiver: fixture.receiver, arguments: arguments,
            returnType: returnType
        ))
    }

    private func door(_ fixture: Fixture) -> (value: PapyrusValue, key: ReferenceKey?) {
        let handle = fixture.handle(Fixture.doorID)
        return (.object(handle), fixture.session.bridge.referenceKey(for: handle))
    }

    @Test func playReturnsTheInstanceAndPlayAndWaitSuspends() throws {
        let fixture = try Fixture.make()
        var plays: [(source: ReferenceKey, token: UInt64?)] = []
        var instance: Int32 = 5
        fixture.session.bridge.gameNatives.playSound = { _, source, token in
            plays.append((source, token))
            return instance
        }
        let source = door(fixture)
        #expect(call(fixture, "Sound", "Play", [source.value], returnType: .integer)
            == .returned(.integer(5)))
        let waiting = call(fixture, "Sound", "PlayAndWait", [source.value], returnType: .boolean)
        let token = try #require(plays.last?.token)
        #expect(waiting == .suspended(.external(token)))
        #expect(token >= PapyrusWorldStateBridge.firstLatentWaitToken)
        #expect(plays.first?.source == source.key)
        #expect(plays.first?.token == nil)
        instance = 0
        #expect(call(fixture, "Sound", "PlayAndWait", [source.value], returnType: .boolean)
            == .returned(.boolean(false)))
    }

    @Test func stopAndVolumeReachTheInstance() throws {
        let fixture = try Fixture.make()
        var stopped: [Int32] = []
        var volumes: [(Int32, Float)] = []
        fixture.session.bridge.gameNatives.stopSound = { stopped.append($0) }
        fixture.session.bridge.gameNatives.setSoundVolume = { volumes.append(($0, $1)) }
        #expect(call(fixture, "Sound", "StopInstance", [.integer(3)]) == .returned(.none))
        #expect(call(fixture, "Sound", "SetInstanceVolume", [.integer(3), .float(0.25)])
            == .returned(.none))
        #expect(stopped == [3])
        #expect(volumes.first?.0 == 3)
        #expect(volumes.first?.1 == 0.25)
    }

    @Test func particleGeometryAppliesAndRemovesWithItsFade() throws {
        let fixture = try Fixture.make()
        var calls: [(ReferenceKey?, Float)] = []
        fixture.session.bridge.gameNatives.setParticleGeometry = { calls.append(($0, $1)) }
        _ = call(fixture, "ShaderParticleGeometry", "Apply", [.float(2)])
        _ = call(fixture, "ShaderParticleGeometry", "Remove", [.float(-1)])
        #expect(calls.count == 2)
        #expect(calls.first?.0 == fixture.key)
        #expect(calls.first?.1 == 2)
        #expect(calls.last?.0 == nil)
        #expect(calls.last?.1 == 0)
    }

    @Test func pathToReferenceWaitsForTheWalk() throws {
        let fixture = try Fixture.make()
        struct Walk {
            let actor: ReferenceKey
            let target: ReferenceKey
            let speed: Float
        }
        var walks: [Walk] = []
        var starts = true
        fixture.session.bridge.gameNatives.pathToReference = { actor, target, speed, _ in
            walks.append(Walk(actor: actor, target: target, speed: speed))
            return starts
        }
        let target = door(fixture)
        let result = call(
            fixture, "Actor", "PathToReference", [target.value, .float(0.5)], returnType: .boolean
        )
        guard case let .suspended(.external(token)) = result else {
            Issue.record("expected a latent wait, got \(result)")
            return
        }
        #expect(token >= PapyrusWorldStateBridge.firstLatentWaitToken)
        #expect(walks.first?.actor == fixture.key)
        #expect(walks.first?.target == target.key)
        #expect(walks.first?.speed == 0.5)
        #expect(call(
            fixture, "Actor", "PathToReference", [target.value, .float(1.5)], returnType: .boolean
        ) == .returned(.boolean(false)))
        #expect(walks.count == 1)
        starts = false
        #expect(call(
            fixture, "Actor", "PathToReference", [target.value, .float(1)], returnType: .boolean
        ) == .returned(.boolean(false)))
    }

    @Test func anAshPileDefaultsAndPassesActivationToItsOwner() throws {
        let fixture = try Fixture.make()
        let trapWorld = FakeTrapWorld()
        fixture.session.bridge.trapWorld = trapWorld
        #expect(call(fixture, "Actor", "AttachAshPile", [.none]) == .returned(.none))
        #expect(trapWorld.placed.first?.base == PapyrusNativeFunctions.defaultAshPile)
        let pile = ReferenceKey.generated(42)
        #expect(fixture.session.bridge.ashPileOwner(of: pile) == fixture.key)
        fixture.session.bridge.activate(pile, by: .player, togglesOpen: false)
        let activation = fixture.session.bridge.referenceState(for: fixture.key)?.activation
        #expect(activation?.activationCount == 1)
    }

    @Test func setEyeTextureHandsTheActorAndTheSetToTheGame() throws {
        let fixture = try Fixture.make()
        var retextured: [(ReferenceKey, ReferenceKey)] = []
        fixture.session.bridge.gameNatives.setEyeTexture = { actor, set in
            retextured.append((actor, set))
            return true
        }
        let set = door(fixture)
        #expect(call(fixture, "Actor", "SetEyeTexture", [set.value]) == .returned(.none))
        #expect(call(fixture, "Actor", "SetEyeTexture", [.none]) == .returned(.none))
        #expect(retextured.count == 1)
        #expect(retextured.first?.0 == fixture.key)
        #expect(retextured.first?.1 == set.key)
    }
}
