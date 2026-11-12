// The cloak's radius unit and the push its spell gives.

@testable import OpenSkyMagic
import Testing

@MainActor
struct CloakKnockTests {
    /// Shield Charge's cloak has magnitude 6: 6 feet, which is 128 units.
    @Test func aCloakOfSixFeetReaches128Units() {
        #expect(abs(6 * MagicCoordinator.CloakPulses.unitsPerFoot - 128) < 0.001)
    }

    @Test func thePushIsTheImpactForceScaledForBipeds() {
        let speed = CloakKnock.speed(impactForce: 50, bipedMultiplier: 0.25, havokScale: 70)
        #expect(speed == 875)
    }

    @Test func noForceOrABadValueGivesNoPush() {
        #expect(CloakKnock.speed(impactForce: 0, bipedMultiplier: 0.25, havokScale: 70) == 0)
        #expect(CloakKnock.speed(impactForce: .nan, bipedMultiplier: 0.25, havokScale: 70) == 0)
        #expect(CloakKnock.speed(impactForce: -5, bipedMultiplier: 0.25, havokScale: 70) == 0)
    }
}
