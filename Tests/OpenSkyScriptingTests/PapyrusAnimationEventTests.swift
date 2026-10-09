// `RegisterForAnimationEvent`: a listener hears one named event from one sender,
// in any letter case, until it unregisters.

@testable import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsPEX
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusAnimationEventTests {
    private static let sender = ReferenceKey.plugin(name: "test.esm", objectID: 2)

    private struct Listening {
        let world: PapyrusWorldRuntime
        let probe: PapyrusWorldProbeDispatch
        let handle: PapyrusObjectHandle
    }

    private func listeningWorld() throws -> Listening {
        let probe = PapyrusWorldProbeDispatch()
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [PapyrusWorldFixture.eventScript("RiderScript", events: [
                ("OnAnimationEvent", PapyrusWorldFixture.probeBody(note: "rider.onanimationevent"))
            ])],
            nativeDispatch: probe
        )
        let references = try PapyrusWorldFixture.index([
            PapyrusWorldFixture.referenceEntry(
                objectID: 1,
                scripts: [.init("RiderScript", properties: [])]
            )
        ])
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: references,
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        PapyrusWorldFixture.drain(world)
        let handle = try #require(world.instancesByKey.values.first)
        return Listening(world: world, probe: probe, handle: handle)
    }

    @Test func aRegisteredListenerHearsTheEvent() throws {
        let listening = try listeningWorld()
        let world = listening.world, handle = listening.handle
        #expect(world.registerAnimationEvent(
            handle: handle,
            sender: Self.sender,
            name: "ExitCartEnd"
        ))
        #expect(world.queueAnimationEvent(sender: Self.sender, name: "exitcartend") == 1)
        #expect(world.queueAnimationEvent(sender: .player, name: "ExitCartEnd") == 0)
        PapyrusWorldFixture.drain(world)
        #expect(listening.probe.notes == ["rider.onanimationevent"])
    }

    @Test func anUnregisteredListenerHearsNothing() throws {
        let listening = try listeningWorld()
        let world = listening.world, handle = listening.handle
        world.registerAnimationEvent(handle: handle, sender: Self.sender, name: "ExitCartEnd")
        world.unregisterAnimationEvent(handle: handle, sender: Self.sender, name: "ExitCartEnd")
        #expect(world.queueAnimationEvent(sender: Self.sender, name: "ExitCartEnd") == 0)
    }
}
