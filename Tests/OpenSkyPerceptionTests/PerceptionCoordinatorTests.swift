// The perception shell over a fake session: which resident actors observe,
// and what the panel reads before and after the pass is wired.

import FeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyPerception
@testable import OpenSkyPerceptionInterface
import simd
import Testing

@MainActor
private final class FakePerceptionSessionWorld: PerceptionSessionWorld {
    var candidates: [PerceptionCandidate] = []
    var targets: [PerceptionTarget] = []

    func perceptionCandidates() -> [PerceptionCandidate] {
        candidates
    }

    func perceptionTargets() -> [PerceptionTarget] {
        targets
    }

    func perceptionHasLineOfSight(from _: SIMD3<Float>, to _: SIMD3<Float>) -> Bool {
        true
    }
}

@MainActor
struct PerceptionCoordinatorTests {
    private static func candidate(
        _ objectID: UInt32,
        isDead: Bool = false,
        isHostile: Bool = false,
        isEngaged: Bool = false,
        hasPackage: Bool = false
    ) -> PerceptionCandidate {
        PerceptionCandidate(
            observer: PerceptionFixture.observer(
                key: .plugin(name: "perception.esm", objectID: objectID)
            ),
            isDead: isDead,
            isHostile: isHostile,
            isEngaged: isEngaged,
            hasPackage: hasPackage
        )
    }

    @Test func onlyLivingActorsTheAIDrivesObserve() {
        let observers = PerceptionCore.observers(from: [
            Self.candidate(1, isHostile: true),
            Self.candidate(2, isEngaged: true),
            Self.candidate(3, hasPackage: true),
            Self.candidate(4),
            Self.candidate(5, isDead: true, isHostile: true)
        ])
        #expect(observers.map(\.key) == [1, 2, 3].map {
            ReferenceKey.plugin(name: "perception.esm", objectID: $0)
        })
    }

    @Test func thePanelIsUnavailableUntilTheSettingsAreWired() {
        let coordinator = PerceptionCoordinator()
        #expect(coordinator.perceptionSnapshot.isUnavailable)
        #expect(coordinator.perceptionLines(for: PerceptionFixture.guardKey).isEmpty)
    }

    @Test func theWiredPassRunsOverTheFilteredRoster() throws {
        let world = FakePerceptionSessionWorld()
        world.candidates = [
            PerceptionCandidate(
                observer: PerceptionFixture.observer(),
                isDead: false,
                isHostile: true,
                isEngaged: false,
                hasPackage: false
            ),
            Self.candidate(9)
        ]
        world.targets = [PerceptionFixture.target(feet: SIMD3(200, 0, 0))]
        let coordinator = PerceptionCoordinator()
        coordinator.attach(world: world)
        coordinator.wire(settings: .synthetic)

        for _ in 0 ..< 60 {
            coordinator.advance(by: PerceptionRuntime.fixedStepSeconds)
        }

        let runtime = try #require(coordinator.runtime)
        #expect(runtime.observers.map(\.key) == [PerceptionFixture.guardKey])
        #expect(!coordinator.perceptionSnapshot.isUnavailable)
        #expect(!coordinator.perceptionLines(for: PerceptionFixture.guardKey).isEmpty)
    }
}
