// The casting graph events: which start event a spell gets, and what a hand raises as
// it charges, readies, and releases. See docs/engine/casting-graph.md.

@testable import OpenSkyFormatsESM
@testable import OpenSkyMagic
import OpenSkyMagicInterface
import Testing

struct CastingGraphEventTests {
    private static let spell = ReferenceKey.generated(7)

    @Test func eachKindOfSpellGetsItsStartEvent() {
        let aimed = CastGraphSpell(castingType: .fireAndForget, delivery: .aimed)
        let selfSpell = CastGraphSpell(castingType: .fireAndForget, delivery: .selfTarget)
        let touch = CastGraphSpell(castingType: .fireAndForget, delivery: .touch)
        let flames = CastGraphSpell(castingType: .concentration, delivery: .aimed)
        let heal = CastGraphSpell(castingType: .concentration, delivery: .selfTarget)
        var ward = heal
        ward.isWard = true
        var telekinesis = ward
        telekinesis.isTelekinesis = true
        let constant = CastGraphSpell(castingType: .constantEffect, delivery: .selfTarget)

        #expect(aimed.startEvent == "SpellAimedStart")
        #expect(CastGraphSpell(castingType: .fireAndForget, delivery: .targetLocation)
            .startEvent == "SpellAimedStart")
        #expect(selfSpell.startEvent == "SpellSelfStart")
        #expect(touch.startEvent == nil)
        #expect(flames.startEvent == "SpellAimedConcentrationStart")
        #expect(heal.startEvent == "SpellSelfConcentrationStart")
        #expect(ward.startEvent == "WardStart")
        #expect(telekinesis.startEvent == "SpellTelekinesisStart")
        #expect(constant.startEvent == nil)
    }

    private static func hand(
        _ phase: SpellCastPhase, concentration: Bool = false, releasing: Bool = false
    ) -> CastingGraphHand {
        var hand = CastingGraphHand(phase: phase, spell: phase == .idle ? nil : spell)
        hand.start = concentration ? "SpellAimedConcentrationStart" : "SpellAimedStart"
        hand.isConcentration = concentration
        hand.isReleasing = releasing
        return hand
    }

    @Test func aFireAndForgetHandStartsReadiesAndReleases() {
        let idle = CastingGraphHand()
        let charging = Self.hand(.charging)
        let ready = Self.hand(.ready)
        let releasing = Self.hand(.ready, releasing: true)

        #expect(CastingGraphEventRule.start(of: .right, from: idle, to: charging)
            == "MRh_SpellAimedStart")
        #expect(CastingGraphEventRule.start(of: .right, from: charging, to: ready) == nil)
        #expect(CastingGraphEventRule.events(.right, from: charging, to: ready, cast: false)
            == ["MRh_SpellReady_Event"])
        #expect(CastingGraphEventRule.events(.left, from: ready, to: releasing, cast: false)
            == ["MLh_SpellRelease_Event"])
        #expect(CastingGraphEventRule.events(.right, from: releasing, to: idle, cast: true)
            .isEmpty)
    }

    /// An NPC's release casts at once, with no latch.
    @Test func anNPCReleaseRaisesTheReleaseEventWhenItCasts() {
        #expect(CastingGraphEventRule.events(
            .right, from: Self.hand(.ready), to: CastingGraphHand(), cast: true
        ) == ["MRh_SpellRelease_Event"])
    }

    @Test func aConcentrationHandReleasesWhenItsChargeIsFull() {
        let charging = Self.hand(.charging, concentration: true)
        let held = Self.hand(.concentrating, concentration: true)
        #expect(CastingGraphEventRule.events(.right, from: charging, to: held, cast: false)
            == ["MRh_SpellRelease_Event"])
        #expect(CastingGraphEventRule.events(
            .right, from: held, to: CastingGraphHand(), cast: false
        ).isEmpty)
    }

    @Test func aConcentrationHandWithNoChargeReleasesRightAfterItsStart() {
        let ready = Self.hand(.ready, concentration: true)
        #expect(
            CastingGraphEventRule.afterStart(.right, state: ready) == ["MRh_SpellRelease_Event"]
        )
        #expect(CastingGraphEventRule.afterStart(
            .left, state: Self.hand(.concentrating, concentration: true)
        ) == ["MLh_SpellRelease_Event"])
        var lead = ready
        lead.isDualLead = true
        #expect(CastingGraphEventRule.afterStart(.right, state: lead) == ["MLh_SpellRelease_Event"])
        let charging = Self.hand(.charging, concentration: true)
        #expect(CastingGraphEventRule.afterStart(.right, state: charging).isEmpty)
        #expect(CastingGraphEventRule.afterStart(.right, state: Self.hand(.ready)).isEmpty)
    }

    @Test func aQueuedStartGoesOutOnlyWhileItsCastStillHolds() {
        let single = "MRh_SpellAimedStart"
        let dual = "DualMagic_SpellAimedStart"
        #expect(CastingGraphEventRule.startStillHolds(single, phase: .charging, dual: false))
        #expect(!CastingGraphEventRule.startStillHolds(single, phase: .idle, dual: false))
        #expect(!CastingGraphEventRule.startStillHolds(single, phase: .charging, dual: true))
        #expect(CastingGraphEventRule.startStillHolds(dual, phase: .charging, dual: true))
    }

    @Test func aDualCastUsesTheLeftHandAndItsOwnStart() {
        let single = Self.hand(.charging)
        var lead = single
        lead.isDualLead = true
        var partner = single
        partner.isDualPartner = true
        var leadReady = Self.hand(.ready)
        leadReady.isDualLead = true

        #expect(CastingGraphEventRule.start(of: .right, from: single, to: lead)
            == "DualMagic_SpellAimedStart")
        #expect(CastingGraphEventRule.start(of: .left, from: CastingGraphHand(), to: partner)
            == nil)
        #expect(CastingGraphEventRule.events(.right, from: lead, to: leadReady, cast: false)
            == ["MLh_SpellReady_Event"])
        #expect(CastingGraphEventRule.events(.left, from: partner, to: partner, cast: true)
            .isEmpty)
        var telekinesis = lead
        telekinesis.start = "SpellTelekinesisStart"
        #expect(CastingGraphEventRule.start(of: .right, from: single, to: telekinesis) == nil)
    }

    @Test func theWantCastNamesFollowTheHand() {
        #expect(CastingGraphNames.wantCast(.left) == "bWantCastLeft")
        #expect(CastingGraphNames.wantCast(.right) == "bWantCastRight")
    }
}
