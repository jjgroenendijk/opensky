// The `World > Crime & Factions` readout wording (issue #507): the reaction
// line names the term that answered and every term beneath it, and the vendor
// line judges the window at the game hour.

import Foundation
@testable import OpenSkyActorsInterface
@testable import OpenSkyEngine
import Testing

struct CrimeFactionReadoutTests {
    @Test
    func theReactionLinesWalkThePrecedenceList() {
        let terms = ReactionTermsReadout(
            decision: HostilityDecision(hostility: .hostile, reaction: .enemy, source: .crime),
            hostilityOverride: nil,
            crime: .enemy,
            relationship: .friend,
            scriptedRank: 1,
            faction: nil
        )
        #expect(CrimeFactionReadout.reactionLines(terms) == [
            "Toward the player: hostile, reaction enemy from crime",
            "  override: none",
            "  crime: enemy",
            "  relationship: friend (scripted rank 1)",
            "  faction relation: none"
        ])
    }

    @Test
    func theResponseNamesWhatAGuardDoes() {
        #expect(CrimeFactionReadout.responseText(.none) == "ignore")
        #expect(CrimeFactionReadout.responseText(.confront(bounty: 40)) == "confront")
        #expect(
            CrimeFactionReadout.responseText(.attackOnSight(bounty: 1000)) == "attack on sight"
        )
    }

    @Test
    func theVendorWindowIsJudgedAtTheGameHour() {
        let open = CrimeFactionPanelTests.snapshot(hour: 12)
        #expect(CrimeFactionReadout.vendorText(for: open).contains("Hours: 8-20 · open now"))
        let closed = CrimeFactionPanelTests.snapshot(hour: 22)
        #expect(CrimeFactionReadout.vendorText(for: closed).contains("closed now"))
        #expect(CrimeFactionReadout.vendorText(for: closed).contains("Fence: no"))
    }

    @Test
    func anUnavailableSnapshotSaysSoEverywhere() {
        let snapshot = CrimeFactionControlSnapshot.unavailable
        for text in [
            CrimeFactionReadout.bountyText(for: snapshot),
            CrimeFactionReadout.theftText(for: snapshot),
            CrimeFactionReadout.membershipText(for: snapshot),
            CrimeFactionReadout.vendorText(for: snapshot)
        ] {
            #expect(text.contains("no game data loaded"))
        }
    }
}
