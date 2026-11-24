// A cast through the coordinator raises its start event on the player's graph a step
// after it began, and the readout names the last graph event.

import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
@testable import OpenSkyMagic
import OpenSkyMagicFixtures
@testable import OpenSkyMagicInterface
import Testing

@MainActor
struct MagicCoordinatorCastingGraphTests {
    @Test func aCastRaisesItsStartEventOnThePlayersGraph() throws {
        let world = FakeMagicWorld()
        let coordinator = try MagicCoordinatorTests.castingWired(world)
        let panels = coordinator.controlPanels
        _ = panels.readSpellTome(
            FormID(SpellbookFixture.Book.healingTome),
            spell: FormID(SpellbookFixture.Spell.healing)
        )
        _ = panels.selectNextKnownSpell()
        _ = panels.readySelectedSpell(in: .right)
        let step = coordinator.frameStep
        var events: [String] = []
        for _ in 0 ..< 3 {
            for case let .playerGraphEvent(name) in step.advanceCasting(
                CastingIntent(rightHeld: true, deltaTime: 0.1),
                isPlayerControlled: true,
                weaponsDrawn: true
            ) {
                events.append(name)
            }
        }
        let start = try #require(events.first)
        #expect(start.hasPrefix("MRh_Spell"))
        #expect(start.hasSuffix("Start"))
        #expect(panels.castingControlSnapshot.castingCueText.contains("graph: "))
        let right = try #require(coordinator.playerCasting()?.hands.first { $0.hand == .right })
        #expect(right.phase != .idle)
        #expect(right.readied != nil)
        #expect(right.pressed)
        #expect(right.wantsCast)
    }

    @Test func theCastingReadoutIsEmptyWithoutACaster() {
        let coordinator = MagicCoordinator(world: FakeMagicWorld())
        #expect(coordinator.playerCasting() == nil)
    }
}
