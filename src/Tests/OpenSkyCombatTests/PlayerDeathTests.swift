// The player at zero health, the fall damage curve, and bleedout recovery.

import Foundation
@testable import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import Testing

@Suite("Player death")
struct PlayerDeathTests {
    @Test
    func aPlayerWhoIsNotEssentialDiesAndReloadsAfterTheDelay() {
        var death = PlayerDeath()
        let dead = PlayerHealthSample(share: 0, isEssential: false)
        #expect(death.advance(by: 0.1, health: dead) == [.die])
        #expect(death.isDead)
        #expect(death.advance(by: 4, health: dead).isEmpty)
        #expect(death.advance(by: 1.5, health: dead) == [.reloadNewestSave])
        #expect(death.advance(by: 1, health: dead).isEmpty)
        death.reset()
        #expect(!death.isDead)
    }

    @Test
    func anEssentialPlayerKneelsAndStandsOnceHealed() {
        var death = PlayerDeath()
        #expect(death
            .advance(by: 0.1, health: .init(share: 0, isEssential: true)) == [.enterBleedout])
        #expect(death.isBleedingOut)
        #expect(death.incomingDamageMult == 0)
        let healed = PlayerHealthSample(share: 0.5, isEssential: true, bleedoutRatio: 0.1)
        #expect(death.advance(by: 1, health: healed).isEmpty)
        #expect(death.advance(by: 5, health: healed) == [.leaveBleedout(restoreHealth: false)])
        #expect(!death.isBleedingOut)
    }

    @Test
    func fallDamageStartsAboveTheMinimumHeight() {
        let settings = FallDamageSettings.vanilla
        #expect(settings.damage(height: 500, speed: 900, isPlayer: true) == 0)
        #expect(settings.damage(height: 900, speed: 500, isPlayer: true) == 0)
        let damage = settings.damage(height: 900, speed: 900, isPlayer: true)
        #expect(abs(damage - powf(30, 1.45)) < 0.01)
        #expect(settings.damage(height: 900, speed: 900, isPlayer: false) > damage)
    }

    @Test
    func aKneelingActorStandsEarlyOnlyAfterTheMinimum() {
        var tracker = BleedoutTracker()
        let actor = ReferenceKey.player
        _ = tracker.enter(actor)
        let settings = DeathSettings.vanilla
        #expect(tracker.advance(by: 1, settings: settings, recovered: { _ in true }).isEmpty)
        let late = tracker.advance(
            by: settings.bleedoutMinSeconds, settings: settings, recovered: { _ in true }
        )
        #expect(late == [actor])
    }
}
