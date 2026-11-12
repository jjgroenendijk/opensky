// The Script binding parts read the session ports, and answer nothing without a session.

import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyPhysics
@testable import OpenSkyScriptAdapters
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct ScriptBindingsTests {
    private let host = ScriptHost()
    private var adapter: ScriptWorldAdapter {
        ScriptWorldAdapter(game: host)
    }

    private static let actor = ReferenceKey.generated(3)
    private static let end = PhysicsLinkEnd(reference: actor, node: "Head", offset: .zero)

    @Test func theScriptWorldReadsTheHUDAndTheStreamer() {
        #expect(adapter.crosshairReference == nil)
        #expect(adapter.referenceKey(formID: FormID(0x10)) == nil)
        #expect(adapter.gameClock == nil)
        #expect(adapter.playerLocation == nil)
        #expect(host.fakeStreamer.referenceEntryFormIDCalls == [FormID(0x10)])
    }

    @Test func musicNeedsAPluginKey() {
        #expect(!adapter.soundBindings.addMusic(Self.actor))
        adapter.soundBindings.removeMusic(.plugin(name: "skyrim.esm", objectID: 0x70))
        adapter.soundBindings.answerSoundWaits()
        #expect(adapter.state.soundWaitAnswers.isEmpty)
    }

    @Test func withoutAWeatherSystemTheSkyIsAtRest() {
        let sky = adapter.skyBindings
        #expect(sky.currentWeather == nil)
        #expect(sky.outgoingWeather == nil)
        #expect(sky.transitionFraction == 1)
        #expect(!sky.setWeather(Self.actor, held: true, instant: false, accelerated: false))
        sky.releaseWeather()
        #expect(sky.candidateWeathers().isEmpty)
        #expect(sky.classification(of: Self.actor) == nil)
        #expect(!sky.changeFog(.power(2), in: FormID(0x20)))
    }

    @Test func withoutRagdollsAConstraintIsRefused() {
        host.fakeStreamer.dynamicBodies = DynamicBodyWorld()
        let physics = adapter.physicsBindings
        #expect(physics.addBallAndSocket(Self.end, Self.end) == .returned(.boolean(false)))
        #expect(!physics.removeConstraints(Self.end, Self.end))
        physics.publishTranslations([:], moves: [:])
    }

    @Test func aNodeOfAnUnknownReferenceIsMissing() {
        let nodes = adapter.nodeBindings
        #expect(nodes.readyNode(of: Self.actor, named: "Head") == nil)
        nodes.answerPathWaits()
        nodes.answerNodeWaits()
        #expect(adapter.state.pathWaitAnswers.isEmpty)
    }

    @Test func theModelNodeLoaderSchedulesItsDrainOnlyWithFiles() {
        let state = adapter.state
        let loader = ScriptModelNodeLoader(game: host, state: state)
        var drains: [() -> Void] = []
        loader.fillModelNodes(files: nil) { drains.append($0) }
        #expect(drains.isEmpty)
        loader.fillModelNodes(files: InMemoryFileSource()) { drains.append($0) }
        #expect(drains.count == 1)
        #expect(state.modelNodes != nil)
        drains.forEach { $0() }
    }

    @Test func anAshPileOfNoKnownReferenceOpensNothing() {
        let bridge = PapyrusWorldStateBridge(worldState: WorldStateStore())
        let interaction = PlacedInteraction(
            reference: FormID(0x10), base: FormID(0x20), position: .zero, name: "Ash Pile",
            action: .search, actionLabel: "Search", sounds: nil
        )
        let event = InteractionEvent(target: InteractionTarget(
            interaction: interaction, hitPosition: .zero, distance: 64
        ))
        adapter.searchAshPileOwner(of: event, bridge: bridge)
        #expect(host.fakeContainerMenu.openCallCount == 0)
    }
}
