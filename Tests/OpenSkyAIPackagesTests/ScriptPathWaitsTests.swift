// `PathToReference` waits: each ends when its actor's walk ends, true on arrival.

@testable import OpenSkyAIPackages
@testable import OpenSkyFormatsESM
import OpenSkyPhysics
import Testing

struct ScriptPathWaitsTests {
    private func readout(_ actor: ReferenceKey, _ state: NPCMovementState) -> NPCMovementReadout {
        NPCMovementReadout(
            actor: actor, state: state, feetPosition: .zero, yaw: 0,
            waypointIndex: 0, waypointCount: 1, gait: .walk, repathCount: 0
        )
    }

    @Test func aWaitEndsWhenTheWalkEnds() {
        var waits = ScriptPathWaits()
        let walker = ReferenceKey.generated(1)
        let quitter = ReferenceKey.generated(2)
        let gone = ReferenceKey.generated(3)
        waits.wait(10, for: walker)
        waits.wait(11, for: quitter)
        waits.wait(12, for: gone)
        #expect(waits.settle([readout(walker, .moving), readout(quitter, .gaveUp)]) == [
            11: false,
            12: false
        ])
        #expect(waits.count == 1)
        #expect(waits.settle([readout(walker, .awaitingRepath)]).isEmpty)
        #expect(waits.settle([readout(walker, .arrived)]) == [10: true])
        #expect(waits.isEmpty)
    }

    @Test func theSpeedPicksWalkOrRun() {
        #expect(ScriptPathWaits.gait(forSpeed: 0) == .walk)
        #expect(ScriptPathWaits.gait(forSpeed: 0.49) == .walk)
        #expect(ScriptPathWaits.gait(forSpeed: 0.5) == .run)
        #expect(ScriptPathWaits.gait(forSpeed: 1) == .run)
    }
}
