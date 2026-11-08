// The combat machine's choices that read the game's settings: walking inside the advance
// radius, keeping the weapon in use, backing off to cast, healing, aimed shouts, and a
// flying actor's stages (docs/engine/combat-behavior.md#game-settings).

@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
import simd
import Testing

@MainActor
struct CombatGameSettingsBehaviorTests {
    private typealias Fixture = CombatBehaviorFixture

    private static let heal = CombatSpellOption(
        spell: .generated(201), cost: 30, range: 0, chargeSeconds: 0.2, purpose: .heal
    )
    private static let shout = CombatSpellOption(
        spell: .generated(301), cost: 0, range: 2000, purpose: .shout, cooldownSeconds: 30
    )

    private static func engaged(
        _ settings: CombatBehaviorSettings, inputs: CombatBehaviorInputs
    ) -> CombatBehaviorMachine {
        var machine = Fixture.machine(settings: settings)
        _ = machine.step(seconds: Fixture.step, inputs: inputs)
        return machine
    }

    @Test func anApproachWalksInsideTheWalkRadius() {
        var settings = Fixture.neverCasting
        settings.walkRadius = 256
        var far = Self.engaged(settings, inputs: Fixture.inputs(distance: 1000))
        #expect(far.phase == .approaching)
        let running = Fixture.run(&far, seconds: 1, inputs: Fixture.inputs(distance: 1000))
        #expect(running.contains { $0.command != nil && !$0.walks })
        let walking = Fixture.run(&far, seconds: 1, inputs: Fixture.inputs(distance: 200))
        #expect(walking.contains { $0.command != nil && $0.walks })
    }

    @Test func theWeaponInUseHoldsPastTheStrikingDistance() {
        var settings = Fixture.neverCasting
        settings.weaponRangeHoldMult = 1.25
        let striking = Fixture.reach - settings.reachSlack
        var machine = Self.engaged(settings, inputs: Fixture.inputs())
        Fixture.run(&machine, until: { $0.phase == .spacing }, inputs: Fixture.inputs())
        _ = machine.step(seconds: Fixture.step, inputs: Fixture.inputs(distance: striking * 1.2))
        #expect(machine.phase == .spacing)
        _ = machine.step(seconds: Fixture.step, inputs: Fixture.inputs(distance: striking * 1.3))
        #expect(machine.phase == .approaching)
    }

    @Test func aCasterTooCloseBacksOffBeforeItCasts() {
        var settings = Fixture.alwaysCasting
        settings.backOffRadius = 256
        let inputs = Fixture.inputs(
            distance: 200, casting: Fixture.casting(magicka: 100, [Fixture.fireball])
        )
        var machine = Fixture.machine(settings: settings)
        let first = Fixture.run(&machine, seconds: 1, inputs: inputs)
        #expect(first.contains {
            if case .flee = $0.command {
                true
            } else {
                false
            }
        })
        #expect(machine.phase == .approaching)
        Fixture.run(&machine, until: { $0.phase == .casting }, inputs: inputs)
        #expect(machine.pendingCast == Fixture.fireball)
    }

    @Test func aHurtCasterHealsItselfBelowTheThreshold() {
        var settings = Fixture.neverCasting
        settings.restoreHealthFraction = 0.6
        let profile = CombatCastingProfile(magicka: 100, heals: [Self.heal])
        var healthy = Fixture.machine(settings: settings)
        Fixture.run(&healthy, seconds: 3, inputs: Fixture.inputs(casting: profile))
        #expect(healthy.castCount == 0)
        var hurt = Fixture.machine(settings: settings)
        Fixture.run(
            &hurt, until: { $0.phase == .casting },
            inputs: Fixture.inputs(healthFraction: 0.5, casting: profile)
        )
        #expect(hurt.pendingCast?.purpose == .heal)
    }

    @Test func aShoutWaitsForItsAimAndFacing() {
        let settings = Fixture.neverCasting
        let profile = CombatCastingProfile(shouts: [Self.shout])
        var inputs = Fixture.inputs(distance: 1000, casting: profile)
        inputs.facingError = 0.5
        var machine = Self.engaged(settings, inputs: inputs)
        Fixture.run(&machine, until: { $0.phase == .casting }, inputs: inputs)
        #expect(machine.pendingCast?.purpose == .shout)
        Fixture.run(&machine, seconds: settings.shoutAimSeconds, inputs: inputs)
        #expect(machine.phase == .casting)
        inputs.facingError = 0.01
        let release = Fixture.run(&machine, until: { $0.phase != .casting }, inputs: inputs)
        #expect(release.last?.releasedCast == Self.shout)
        #expect(machine.shoutCooldown > 29)
    }

    @Test func aShoutFacingAwayGivesUpAndWaitsTheRetryTime() {
        let settings = Fixture.neverCasting
        var inputs = Fixture.inputs(
            distance: 1000, casting: CombatCastingProfile(shouts: [Self.shout])
        )
        inputs.facingError = 1
        var machine = Self.engaged(settings, inputs: inputs)
        Fixture.run(&machine, until: { $0.phase == .casting }, inputs: inputs)
        let steps = Fixture.run(&machine, until: { $0.phase != .casting }, inputs: inputs)
        #expect(steps.last?.cancelledCast == true)
        #expect(machine.shoutCooldown > settings.shoutRetrySeconds - 0.1)
    }

    @Test func aSpellPastTheRangeCapIsNotCast() {
        var settings = Fixture.alwaysCasting
        settings.spellRangeCap = 500
        let inputs = Fixture.inputs(
            distance: 1000, casting: Fixture.casting(magicka: 100, [Fixture.fireball])
        )
        #expect(inputs.castableSpell(settings: settings) == nil)
        settings.spellRangeCap = 5000
        #expect(inputs.castableSpell(settings: settings) == Fixture.fireball)
    }

    @Test func aFlyingActorCirclesAndDoesNotSwingInTheAir() {
        let settings = Fixture.neverCasting
        var inputs = Fixture.inputs()
        inputs.flies = true
        var machine = Self.engaged(settings, inputs: inputs)
        let air = Fixture.run(&machine, seconds: 3, inputs: inputs)
        #expect(machine.flight.stage == .air)
        #expect(air.allSatisfy { !$0.startedAttack })
        let orbit = air.compactMap { $0.command?.destination }.last ?? .zero
        #expect(abs(simd_length(orbit) - settings.flight.orbitDistance) < 1)
        Fixture.run(&machine, until: { $0.flight.stage != .air }, inputs: inputs)
        #expect(machine.flight.stage != .air)
    }
}

struct CombatGameSettingsMappingTests {
    @Test func theStylePicksTheRadiiBetweenTheThreeSettings() {
        let radii = CombatRadii(low: 128, mid: 256, high: 512)
        #expect(radii.radius(at: 0) == 128)
        #expect(radii.radius(at: 0.5) == 256)
        #expect(radii.radius(at: 1) == 512)
        #expect(radii.radius(at: 0.75) == 384)
        #expect(radii.radius(at: 4) == 512)
        #expect(radii.radius(at: .nan) == 256)
    }

    @Test func theNeutralStyleWalksAtTheMidRadiusAndNeverBacksOff() {
        let settings = CombatAISettings.vanilla.applyingRanges(to: .standard, tuning: nil)
        #expect(settings.walkRadius == 256)
        #expect(settings.backOffRadius == 0)
        #expect(settings.weaponRangeHoldMult == 1.25)
        #expect(settings.weaponAbsoluteRangeMult == 4)
        #expect(settings.spellRangeCap == 15000)
        #expect(settings.restoreHealthFraction == 0.6)
        #expect(abs(settings.shoutToleranceRadians - 5 * .pi / 180) < 1e-6)
    }

    @Test func anAggressiveStyleRunsInCloserAndADefensiveOneBacksOff() {
        var tuning = CombatStyleTuning.neutral
        tuning.offensiveMultiplier = 1
        tuning.defensiveMultiplier = 1
        let settings = CombatAISettings.vanilla.applyingRanges(to: .standard, tuning: tuning)
        #expect(settings.walkRadius == 128)
        #expect(settings.backOffRadius == 256)
    }

    @Test func theFlightTimesFollowTheStyle() {
        var style = CombatStyleTuning.FlightStyle()
        let base = CombatAISettings.vanilla.flight(style: style)
        #expect(base.groundSeconds == 12.5)
        #expect(base.airSeconds == 5.5)
        #expect(base.perchSeconds == 4)
        style.hoverTime = 1
        style.groundAttackTime = 0
        style.perchAttackTime = 0
        let tuned = CombatAISettings.vanilla.flight(style: style)
        #expect(tuned.airSeconds == 11)
        #expect(tuned.groundSeconds == 8)
        #expect(tuned.perchSeconds == 4)
    }

    @Test func theCycleGoesFromTheAirToAPerchOrTheGroundAndBack() {
        var cycle = CombatFlightCycle()
        var flight = CombatFlightSettings()
        flight.airSeconds = 1
        flight.perchSeconds = 1
        #expect(!cycle.advance(seconds: 0.5, settings: flight) { 0 })
        #expect(cycle.advance(seconds: 0.5, settings: flight) { 0 })
        #expect(cycle.stage == .perch)
        #expect(cycle.advance(seconds: 1, settings: flight) { 0 })
        #expect(cycle.stage == .air)
        #expect(cycle.advance(seconds: 1, settings: flight) { 0.9 })
        #expect(cycle.stage == .ground)
    }

    @Test func aHealNeedsASelfAimedFriendlyRestore() {
        let option = CombatSpellOption(spell: .generated(1), cost: 10, range: 0)
        let heal = CombatSpellCandidate(
            option: option, isSpell: true, targetsSelf: true, isDeliverable: true,
            isHostile: false, fitsHand: true, restoresHealth: true
        )
        #expect(CombatCore.healOption(heal)?.purpose == .heal)
        #expect(CombatCore.spellOption(heal) == nil)
        let ward = CombatSpellCandidate(
            option: option, isSpell: true, targetsSelf: true, isDeliverable: true,
            isHostile: false, fitsHand: true
        )
        #expect(CombatCore.healOption(ward) == nil)
    }

    @Test func theReadoutNamesTheGameSettingsOrSaysTheyAreOff() {
        let readout = CombatStyleReadout(tuning: nil, base: .standard)
        #expect(readout.gameSettingsText(.vanilla, isOn: false)
            == "Game combat settings: off (OpenSky's numbers)")
        let text = readout.gameSettingsText(.vanilla, isOn: true)
        #expect(text.hasPrefix("Advance: walk inside 256 u, back off to 0 u"))
        #expect(text.contains("Flight: orbit 4000 u, air 5.5 s, perch 4.0 s (50%), ground 12.5 s"))
    }
}
