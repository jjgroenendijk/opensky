// The perk shell over the fixture load order: ownership writes, the one-time
// `PRKR` seed, and what an entry point answers with and without a runtime.

import FeaturesTesting
import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyProgression
import OpenSkyProgressionInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PerkCoordinatorTests {
    private let blocking = PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.blocking)
    private let bandit = ReferenceKey.plugin(name: "perkruntime.esm", objectID: 0x0900)
    private let banditBase: UInt32 = 0x0500

    private func coordinator(
        world: FakeProgressionWorld,
        baselines: ActorPerkBaselineResolver? = nil
    ) throws -> PerkCoordinator {
        let index = try PerkRuntimeFixture.index()
        let coordinator = PerkCoordinator()
        coordinator.attach(world: world)
        coordinator.wire(
            PerkRuntime(
                store: WorldStateStore(),
                perks: PerkRuntimeFixture.perkStore(index: index),
                conditionRegistry: .empty
            ),
            baselines: baselines,
            pluginName: PerkRuntimeFixture.pluginName
        )
        return coordinator
    }

    private var banditHolder: ActorValueHolder {
        ActorValueHolder(key: bandit, subject: .actor(base: FormID(banditBase)))
    }

    @Test func withoutARuntimeEveryEntryPointKeepsItsValue() {
        let coordinator = PerkCoordinator()
        coordinator.attach(world: FakeProgressionWorld())

        #expect(coordinator.modified(10, at: PerkRuntimeFixture.percentBlocked, on: .player) == 10)
        #expect(coordinator.multiplier(at: PerkRuntimeFixture.percentBlocked, on: .player) == 1)
        #expect(coordinator.ownership(of: .player) == nil)
        #expect(!coordinator.add(blocking, to: .player))
    }

    @Test func addingAPerkSharesTheRuntimeAndReconcilesOnce() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)
        let changesAfterWire = world.changeCount

        #expect(coordinator.add(blocking, to: .player))
        #expect(!coordinator.add(blocking, to: .player))

        #expect(world.changeCount == changesAfterWire + 2)
        #expect(world.reconciled == [.player])
        #expect(coordinator.ownership(of: .player) == [blocking])
    }

    @Test func removingAPerkReconcilesOnlyWhenItWasOwned() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)

        #expect(!coordinator.remove(blocking, from: .player))
        coordinator.add(blocking, to: .player)
        #expect(coordinator.remove(blocking, from: .player))

        #expect(world.reconciled == [.player, .player])
    }

    @Test func anOwnedPerkScalesItsEntryPoint() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)
        coordinator.add(blocking, to: .player)

        #expect(coordinator.multiplier(at: PerkRuntimeFixture.percentBlocked, on: .player) == 1.25)
    }

    @Test func anUnknownActorAnswersTheIdentity() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)

        #expect(coordinator.multiplier(at: PerkRuntimeFixture.percentBlocked, on: bandit) == 1)
        #expect(coordinator.ownership(of: bandit) == nil)
    }

    @Test func anActorIsSeededFromItsPerkRunOnce() throws {
        let world = FakeProgressionWorld()
        world.residents[bandit] = banditHolder
        let baselines = try ActorSpellFixture.perkResolver(npcs: [
            ActorSpellFixture.npc(formID: banditBase, perks: [PerkRuntimeFixture.Perk.blocking])
        ])
        let coordinator = try coordinator(world: world, baselines: baselines)

        #expect(coordinator.ownership(of: bandit) == [blocking])
        #expect(coordinator.seed(banditHolder) == 0)
        #expect(world.reconciled == [bandit])
    }
}
