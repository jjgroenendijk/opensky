// The shot state machine over the census-named event stream (issue #196,
// roadmap item 15.5, scope point 2).
//
// A list of strings in, a state out — which is what keeping `ArcheryState` free
// of any clock, world or projectile buys. Every name here comes from the M14
// behavior census and is spelled the way `0_master.hkx` spells it; see
// `ArcheryGraphNames`.

@testable import opensky
import Testing

struct ArcheryStateTests {
    @Test func aFullDrawAndLooseWalksTheWholePhaseSequence() {
        var state = ArcheryState()

        let changes = state.handle([
            ArcheryGraphNames.arrowAttach,
            ArcheryGraphNames.bowDraw,
            ArcheryGraphNames.bowDrawn,
            ArcheryGraphNames.arrowRelease
        ])

        #expect(changes.map(\.phase) == [.nocked, .drawing, .drawn, .loosed])
        #expect(changes.first?.attachedArrow == true)
        #expect(changes.last?.loosedArrow == true)
        #expect(state.shotCount == 1)
        #expect(state.shotID == 1)
    }

    @Test func theReleaseFrameLastsOneBatch() {
        var state = ArcheryState()
        state.handle([ArcheryGraphNames.arrowAttach, ArcheryGraphNames.arrowRelease])

        #expect(state.phase == .loosed)
        state.endFrame()
        #expect(state.phase == .idle)
    }

    /// `bBowDrawn` is written off `isFullyDrawn`, so only the drawn phase is
    /// allowed to report it.
    @Test func onlyTheDrawnPhaseReportsAFullDraw() {
        var state = ArcheryState()

        state.handle(ArcheryGraphNames.arrowAttach)
        #expect(state.phase.isDrawing)
        #expect(state.phase.isFullyDrawn == false)

        state.handle(ArcheryGraphNames.bowDrawn)
        #expect(state.phase.isFullyDrawn)
    }

    @Test func aResetAbandonsTheDrawAndDropsTheArrow() {
        var state = ArcheryState()
        state.handle([ArcheryGraphNames.arrowAttach, ArcheryGraphNames.bowDrawn])

        state.handle(ArcheryGraphNames.bowReset)

        #expect(state.phase == .idle)
        #expect(state.hasArrowAttached == false)
        #expect(state.shotCount == 0)
    }

    @Test func detachDropsTheArrowWithoutEndingTheShot() {
        var state = ArcheryState()
        state.handle([ArcheryGraphNames.arrowAttach, ArcheryGraphNames.arrowRelease])

        state.handle(ArcheryGraphNames.arrowDetach)

        #expect(state.hasArrowAttached == false)
        #expect(state.phase == .loosed)
    }

    /// Every name the graph fires that this machine does not act on is dropped
    /// silently — the normal case, since `0_master.hkx` declares 1,217 events.
    @Test func unrecognizedNamesAreIgnored() {
        var state = ArcheryState()

        let changes = state.handle([
            "jumpUp", CombatGraphNames.hitFrame, "SoundPlay.WPNBowZoomIn", "moveStart"
        ])

        #expect(changes.isEmpty)
        #expect(state.phase == .idle)
    }

    /// A graph that reports a release without ever having reported a nock has
    /// still loosed an arrow, and refusing it would drop a real shot to protect
    /// a state machine's tidiness.
    @Test func aReleaseWithNoNockStillCountsAsAShot() {
        var state = ArcheryState()

        let changes = state.handle(ArcheryGraphNames.arrowRelease)

        #expect(changes?.loosedArrow == true)
        #expect(state.shotCount == 1)
        #expect(state.shotID == 1)
    }

    @Test func eachDrawGetsItsOwnShotIdentifier() {
        var state = ArcheryState()

        state.handle([ArcheryGraphNames.arrowAttach, ArcheryGraphNames.arrowRelease])
        state.endFrame()
        state.handle([ArcheryGraphNames.arrowAttach, ArcheryGraphNames.arrowRelease])

        #expect(state.shotID == 2)
        #expect(state.shotCount == 2)
    }

    @Test func resetForgetsEverything() {
        var state = ArcheryState()
        state.handle([ArcheryGraphNames.arrowAttach, ArcheryGraphNames.arrowRelease])

        state.reset()

        #expect(state.phase == .idle)
        #expect(state.shotCount == 0)
        #expect(state.shotID == 0)
        #expect(state.hasArrowAttached == false)
    }

    /// The names are the census's, not this engine's invention. Pinned so a
    /// rename has to be deliberate — a merely plausible name resolves to
    /// nothing at all in a graph declaring 1,217 events.
    @Test func theCensusNamesArePinnedExactly() {
        #expect(ArcheryGraphNames.bowDrawStart == "bowDrawStart")
        #expect(ArcheryGraphNames.bowReset == "bowReset")
        #expect(ArcheryGraphNames.arrowAttach == "arrowAttach")
        #expect(ArcheryGraphNames.bowDrawn == "bowDrawn")
        #expect(ArcheryGraphNames.arrowRelease == "arrowRelease")
        #expect(ArcheryGraphNames.arrowDetach == "arrowDetach")
        #expect(ArcheryGraphNames.bowDraw == "BowDraw")
        #expect(ArcheryGraphNames.bowRelease == "BowRelease")
        #expect(ArcheryGraphNames.isBowDrawn == "bBowDrawn")
        // The release is melee's, reused rather than duplicated.
        #expect(ArcheryGraphNames.attackRelease == CombatGraphNames.attackRelease)
    }
}
