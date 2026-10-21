// The casting hands' cues as pure rules: which MGEF sound kind starts and stops at each
// step of a cast, when the casting art shows, and how a release waits for its event.
// Semantics: CK wiki "Magic Effect", Sounds and Visual Effects.

@testable import OpenSkyFormatsESM
@testable import OpenSkyMagic
import OpenSkyMagicInterface
import Testing

struct CastingCueTests {
    private static let flames = ReferenceKey.plugin(name: "base.esm", objectID: 0x700)

    private static func hand(_ phase: SpellCastPhase, concentration: Bool = false)
        -> CastingHandView
    {
        CastingHandView(
            phase: phase, spell: phase == .idle ? nil : flames, isConcentration: concentration
        )
    }

    @Test func aPressChargesAndShowsTheCastingArt() {
        let cues = CastingCueRule.cues(from: Self.hand(.idle), to: Self.hand(.charging), cast: nil)
        #expect(cues == [
            CastingCue(.sound(.charge), starts: true, spell: Self.flames),
            CastingCue(.art(dual: false), starts: true, spell: Self.flames)
        ])
    }

    @Test func reachingReadySwapsTheChargeSoundForTheReadySound() {
        let cues = CastingCueRule.cues(from: Self.hand(.charging), to: Self.hand(.ready), cast: nil)
        #expect(cues == [
            CastingCue(.sound(.charge), starts: false, spell: Self.flames),
            CastingCue(.sound(.ready), starts: true, spell: Self.flames)
        ])
    }

    /// Release "plays when the player releases the button and successfully casts".
    @Test func onlyACastReleaseSoundsTheRelease() {
        let cast = CastingCueRule.cues(
            from: Self.hand(.ready), to: Self.hand(.idle), cast: Self.flames
        )
        #expect(cast.contains(CastingCue(.sound(.release), starts: true, spell: Self.flames)))
        #expect(cast.contains(CastingCue(.art(dual: false), starts: false, spell: Self.flames)))

        let cancelled = CastingCueRule.cues(
            from: Self.hand(.ready), to: Self.hand(.idle), cast: nil
        )
        #expect(!cancelled.contains { $0.what == .sound(.release) })
    }

    /// Charge is for fire-and-forget spells; a concentration spell loops its Cast Loop.
    @Test func aConcentrationSpellLoopsItsCastLoopOnly() {
        let charging = CastingCueRule.cues(
            from: Self.hand(.idle), to: Self.hand(.charging, concentration: true), cast: nil
        )
        #expect(!charging.contains { $0.what == .sound(.charge) })
        let held = CastingCueRule.cues(
            from: Self.hand(.charging, concentration: true),
            to: Self.hand(.concentrating, concentration: true),
            cast: nil
        )
        #expect(held == [CastingCue(.sound(.castLoop), starts: true, spell: Self.flames)])
    }

    @Test func drawingOrSheathingSoundsEachReadiedSpellOnce() {
        let cues = CastingCueRule.drawCues(
            drawn: false, now: true, readied: [Self.flames, Self.flames]
        )
        #expect(cues == [CastingCue(.sound(.drawSheathe), starts: true, spell: Self.flames)])
        #expect(CastingCueRule.drawCues(drawn: nil, now: true, readied: [Self.flames]).isEmpty)
        #expect(CastingCueRule.drawCues(drawn: true, now: true, readied: [Self.flames]).isEmpty)
    }

    @Test func aReleaseWaitsForItsHandsSpellFireEvent() {
        var latch = SpellReleaseLatch()
        let released = latch.hold(.right, pressed: false, phase: .ready, fired: false, delta: 0.05)
        #expect(released && latch.isWaiting(.right))
        let waiting = latch.hold(.right, pressed: false, phase: .ready, fired: false, delta: 0.05)
        #expect(waiting)
        let fired = latch.hold(.right, pressed: false, phase: .ready, fired: true, delta: 0.05)
        #expect(!fired && !latch.isWaiting(.right))
    }

    @Test func aReleaseWithoutAGraphFiresAfterTheWait() {
        var latch = SpellReleaseLatch()
        var held = latch.hold(.left, pressed: false, phase: .ready, fired: false, delta: 0)
        var frames = 0
        while held, frames < 100 {
            held = latch.hold(.left, pressed: false, phase: .ready, fired: false, delta: 0.1)
            frames += 1
        }
        #expect(frames == 4)
    }

    @Test func aChargingHandIsNotHeldBack() {
        var latch = SpellReleaseLatch()
        let held = latch.hold(.right, pressed: false, phase: .charging, fired: false, delta: 0.1)
        #expect(!held && !latch.isWaiting(.right))
    }
}
