// The actor-value shell over a fake world: regeneration skips casters, and the
// panel controls act on the selected target and report what they did.

@testable import OpenSkyActors
import OpenSkyActorsInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorldState
import Testing

@MainActor
final class FakeActorValueWorld: ActorValueWorld {
    var residents: [ActorValueHolder] = []
    var nearest: ActorValueHolder?
    var casting: Set<ReferenceKey> = []

    func regeneratingHolders() -> [ActorValueHolder] {
        [.player] + residents
    }

    func nearestActorValueHolder() -> ActorValueHolder? {
        nearest
    }

    func isCasting(_ key: ReferenceKey) -> Bool {
        casting.contains(key)
    }
}

@MainActor
struct ActorValueCoordinatorTests {
    private static let health: Int32 = 24
    private let actor = ActorValueHolder(
        key: .plugin(name: "skyrim.esm", objectID: 0x0001_3BAC),
        subject: .actor(base: FormID(0x0001_3BAC))
    )

    private func coordinator(world: FakeActorValueWorld) -> ActorValueCoordinator {
        let coordinator = ActorValueCoordinator(store: WorldStateStore())
        coordinator.attach(world: world)
        coordinator.wire(baselines: ActorValueBaselineResolver(
            fallback: ActorValueBaseline(
                maximums: ActorValues(health: 100, magicka: 80, stamina: 60),
                regenPercentPerSecond: ActorValues(health: 50, magicka: 0, stamina: 0)
            )
        ))
        return coordinator
    }

    @Test func withoutGameDataThePanelIsUnavailable() {
        let coordinator = ActorValueCoordinator(store: WorldStateStore())

        #expect(coordinator.snapshot == .unavailable)
        #expect(coordinator
            .damageSelected(by: 10) == "Actor values unavailable: no game data loaded.")
    }

    @Test func aCasterDoesNotRegenerate() throws {
        let world = FakeActorValueWorld()
        world.residents = [actor]
        world.casting = [actor.key]
        let coordinator = coordinator(world: world)
        let runtime = try #require(coordinator.runtime)
        runtime.damage(.health, by: 50, on: .player)
        runtime.damage(.health, by: 50, on: actor)

        coordinator.advance(delta: 0.1)

        #expect(runtime.current(of: .player).health > 50)
        #expect(runtime.current(of: actor).health == 50)
    }

    @Test func damageReportsTheSelectedValueAfterwards() {
        let coordinator = coordinator(world: FakeActorValueWorld())
        coordinator.selection = Self.health

        let text = coordinator.damageSelected(by: 30)

        #expect(text == "Damaged Player Health: now 70.0.")
        #expect(coordinator.lastActionText == text)
        #expect(coordinator.snapshot.runtimeActorCount == 1)
    }

    @Test func anIndexThatIsNoActorValueIsNamed() {
        let coordinator = coordinator(world: FakeActorValueWorld())
        coordinator.selection = 9999

        #expect(coordinator.setSelectedValue(to: 5).hasSuffix("is not an actor value."))
    }

    @Test func theNearestTargetNeedsAResidentActor() {
        let world = FakeActorValueWorld()
        let coordinator = coordinator(world: world)
        coordinator.target = .nearestActor

        #expect(coordinator.restoreSelectedFully() == "No resident actor to act on.")

        world.nearest = actor
        #expect(coordinator.snapshot.nearestActor?.name == ActorValueCoordinator.name(of: actor))
        #expect(coordinator.restoreSelectedFully().hasPrefix("Refilled \(actor.key.description)"))
    }

    @Test func resetDropsTheStoredValuesOnce() {
        let coordinator = coordinator(world: FakeActorValueWorld())
        coordinator.damageSelected(by: 10)

        #expect(coordinator.resetSelected() == "Reset Player to derived values.")
        #expect(coordinator.resetSelected() == "Player already reads from records.")
    }
}
