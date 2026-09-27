// Env-gated acceptance for the crime runtime over the user's own read-only
// load order (issue #504, roadmap item 21.5).
//
// The question the milestone asks: in a real owned Whiterun interior, does
// taking an owned item while somebody is watching accrue the theft bounty on
// Whiterun's own crime faction and mark the stack stolen — and does the same
// take, unwitnessed, accrue nothing while still marking it?
//
// Every step runs through the production types: the cell is built by
// `CellSceneBuilder`, its `XOWN` is decoded by `Cell`, the crime faction is
// walked out of the `XLCN` chain by `CrimeFactionResolver`, the bounty is
// priced from the FACT's own `CRVA` by `CrimeGoldTable`, and the take goes
// through `WorldItemRuntime.take`.
//
// Counts, editor IDs and derived verdicts only — no game bytes leave the run
// (AGENTS.md "Legal & IP boundary").

import Foundation
import Metal
@testable import opensky
import Testing

struct CrimeRealDataTests {
    /// Internal rather than private: the harness half of this suite lives in
    /// `CrimeRealDataFixture.swift` and reads it (openskyTests/AGENTS.md).
    static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    static let device: MTLDevice? = {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    static var canRun: Bool {
        dataRoot != nil && device != nil
    }

    /// Belethor's shop: an owned Whiterun interior. Located by editor ID rather
    /// than by FormID so a patch that moves the record does not break the
    /// suite; `openskycli record WhiterunBelethorsGeneralGoods` on this install
    /// reports one `XOWN` field and an `XLCN`, and Breezehome — the house the
    /// player buys — reports neither, which is what makes this the right cell.
    static let shopEditorID = "WhiterunBelethorsGeneralGoods"
    /// The faction the location chain is expected to arrive at.
    static let crimeFactionEditorID = "CrimeFactionWhiterun"

    // MARK: - The acceptance

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func takingAnOwnedItemInAWhiterunShopAccruesTheTheftBountyWhenSeen() throws {
        let harness = try Self.harness()
        let candidate = harness.dearestOwnedTakeable()
        // Printed before the requirement, so a cell that stopped placing owned
        // goods says what it does have rather than dumping a built scene.
        print(
            "[INFO] \(Self.shopEditorID): crime faction "
                + "\(harness.crimeFactionName), owned takeables "
                + "\(harness.ownedTakeableCount) of \(harness.takeableCount), "
                + "target \(candidate.map { "\($0.interaction.name) worth \($0.value)" } ?? "none")"
        )
        let theft = try #require(candidate, "the shop placed no owned item worth stealing")

        // Witnessed: the bounty the FACT prices, and a marked stack.
        let watched = try Self.harness()
        watched.reporter.witnesses = FixedCrimeWitnesses(
            watching: .player, by: [.generated(1)]
        )
        let seen = try watched.items.take(theft.interaction)

        #expect(seen.stolen)
        #expect(seen.bounty == theft.expectedBounty)
        #expect(seen.bounty > 0, "a real shop item priced the theft at nothing")
        #expect(watched.reporter.runtime.crimeGold(of: harness.crimeFaction) == seen.bounty)
        #expect(watched.reporter.runtime.crimeCounts(of: harness.crimeFaction).theft == 1)
        #expect(
            watched.items.inventory.stolenCount(of: theft.interaction.base, in: .player)
                == seen.count
        )

        // Unwitnessed: nothing owed, and the goods are still marked — "even if
        // you were able to steal the item without being detected"
        // (<https://en.uesp.net/wiki/Skyrim:Crime>).
        let unseen = try harness.items.take(theft.interaction)

        #expect(unseen.stolen)
        #expect(unseen.bounty == 0)
        #expect(harness.reporter.runtime.crimeGold(of: harness.crimeFaction) == 0)
        #expect(harness.reporter.runtime.crimeCounts(of: harness.crimeFaction).theft == 1)
        #expect(
            harness.items.inventory.stolenCount(of: theft.interaction.base, in: .player)
                == unseen.count
        )
    }

    /// The two record facts the acceptance rests on, asserted on their own so a
    /// failure says which half moved: the shop's cell is owned, and its
    /// location chain arrives at Whiterun's crime faction.
    @Test(.enabled(if: Self.canRun))
    @MainActor
    func theShopCellIsOwnedAndItsLocationChainNamesWhiterunsCrimeFaction() throws {
        let harness = try Self.harness()

        let ownership = try #require(
            harness.scene.owner, "\(Self.shopEditorID) carries no XOWN on this install"
        )
        let owner = try #require(harness.ownership.owner(of: ownership))
        #expect(harness.scene.locationLink != nil)
        #expect(harness.crimeFactionName == Self.crimeFactionEditorID)
        print(
            "[INFO] \(Self.shopEditorID) owner \(owner), crime faction "
                + "\(harness.crimeFactionName), CRVA "
                + "\(harness.crimeValuesDescription)"
        )

        // The player owns no NPC_ record and is in no faction, so the shop's
        // contents are not theirs whichever kind of owner it turns out to be.
        #expect(CrimeActor.player.verdict(on: owner).isTheft)
    }
}
