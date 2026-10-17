// The actor-value shell over a fake world: casting and combat slow regeneration, and the
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
    var fighting: Set<ReferenceKey> = []
    var sprintLoad: Float?
    private(set) var sprintAllowed = true

    func regeneratingHolders() -> [ActorValueHolder] {
        [.player] + residents
    }

    func nearestActorValueHolder() -> ActorValueHolder? {
        nearest
    }

    func isCasting(_ key: ReferenceKey) -> Bool {
        casting.contains(key)
    }

    func isInCombat(_ key: ReferenceKey) -> Bool {
        fighting.contains(key)
    }

    func playerSprintLoad() -> Float? {
        sprintLoad
    }

    func setPlayerSprintAllowed(_ allowed: Bool) {
        sprintAllowed = allowed
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
                regenPercentPerSecond: ActorValues(health: 50, magicka: 50, stamina: 0)
            )
        ))
        return coordinator
    }

    @Test func withoutGameDataThePanelIsUnavailable() {
        let coordinator = ActorValueCoordinator(store: WorldStateStore())

        #expect(coordinator.snapshot == .unavailable)
        #expect(coordinator
            .damageSelected(by: 10).text == "Actor values unavailable: no game data loaded.")
    }

    @Test func aCasterRegeneratesHealthButNotMagicka() throws {
        let world = FakeActorValueWorld()
        world.residents = [actor]
        world.casting = [actor.key]
        let coordinator = coordinator(world: world)
        let runtime = try #require(coordinator.runtime)
        runtime.damage(.health, by: 50, on: actor)
        runtime.damage(.magicka, by: 50, on: actor)

        for _ in 0 ..< 10 {
            coordinator.advance(delta: 0.1)
        }

        #expect(runtime.current(of: actor).health > 50)
        #expect(runtime.current(of: actor).magicka == 30)
    }

    @Test func combatSlowsTheFighterOnly() throws {
        let world = FakeActorValueWorld()
        world.residents = [actor]
        world.fighting = [actor.key]
        let coordinator = coordinator(world: world)
        let runtime = try #require(coordinator.runtime)
        runtime.damage(.magicka, by: 50, on: actor)
        runtime.damage(.magicka, by: 50, on: .player)

        for _ in 0 ..< 10 {
            coordinator.advance(delta: 0.1)
        }

        #expect(runtime.current(of: actor).magicka < runtime.current(of: .player).magicka)
    }

    /// 7 a second at 10 worn weight is 8.4 a second, so 60 stamina lasts about 7 s.
    @Test func sprintingDrainsStaminaUntilTheSprintStops() throws {
        let world = FakeActorValueWorld()
        world.sprintLoad = 10
        let coordinator = coordinator(world: world)
        let runtime = try #require(coordinator.runtime)

        coordinator.advance(delta: 1)
        #expect(abs(runtime.current(of: .player).stamina - 51.6) < 1e-3)
        #expect(world.sprintAllowed)
        for _ in 0 ..< 7 {
            coordinator.advance(delta: 1)
        }
        #expect(runtime.current(of: .player).stamina == 0)
        #expect(!world.sprintAllowed)
    }

    @Test func damageReportsTheSelectedValueAfterwards() {
        let coordinator = coordinator(world: FakeActorValueWorld())
        coordinator.selection = Self.health

        let text = coordinator.damageSelected(by: 30).text

        #expect(text == "Damaged Player Health: now 70.0.")
        #expect(coordinator.lastAction.text == text)
        #expect(coordinator.snapshot.runtimeActorCount == 1)
    }

    @Test func anIndexThatIsNoActorValueIsNamed() {
        let coordinator = coordinator(world: FakeActorValueWorld())
        coordinator.selection = 9999

        #expect(coordinator.setSelectedValue(to: 5).text.hasSuffix("is not an actor value."))
    }

    @Test func theNearestTargetNeedsAResidentActor() {
        let world = FakeActorValueWorld()
        let coordinator = coordinator(world: world)
        coordinator.target = .nearestActor

        #expect(coordinator.restoreSelectedFully().text == "No resident actor to act on.")

        world.nearest = actor
        #expect(coordinator.snapshot.nearestActor?.name == ActorValueCoordinator.name(of: actor))
        #expect(coordinator.restoreSelectedFully().text
            .hasPrefix("Refilled \(actor.key.description)"))
    }

    @Test func resetDropsTheStoredValuesOnce() {
        let coordinator = coordinator(world: FakeActorValueWorld())
        coordinator.damageSelected(by: 10)

        #expect(coordinator.resetSelected().text == "Reset Player to derived values.")
        #expect(coordinator.resetSelected().text == "Player already reads from records.")
    }
}
