// Which faction answers for a place (issue #504, roadmap item 21.5).
//
// The rule the suite pins is the one the local install demonstrates: a shop
// names no crime faction, its city names none either, and the hold two steps up
// names one. `WhiterunBelethorsGeneralGoodsLocation -> WhiterunLocation ->
// WhiterunHoldLocation (FNAM)`, observed with `openskycli record`.

import Foundation
@testable import opensky
import Testing

struct CrimeFactionResolverTests {
    @Test
    func theFirstAuthoredFNAMUpTheParentChainDecides() throws {
        let resolver = try CrimeFixture.crimeFactions()
        let shop = try CrimeFixture.cell(location: CrimeFixture.Locations.shop)

        let faction = try #require(
            resolver.crimeFaction(in: shop, fromPlugin: CrimeFixture.pluginName)
        )
        #expect(faction.editorID == "CrimeFactionHold")
        #expect(
            resolver.crimeFactionKey(in: shop, fromPlugin: CrimeFixture.pluginName)
                == CrimeFixture.key(CrimeFixture.Factions.hold)
        )
    }

    /// A chain that names no crime faction anywhere has none, and that is a
    /// real answer rather than a gap: a stretch of road belongs to nobody.
    @Test
    func aChainWithNoCrimeFactionAnswersNone() throws {
        let resolver = try CrimeFixture.crimeFactions()
        let wilderness = try CrimeFixture.cell(location: CrimeFixture.Locations.wilderness)

        #expect(resolver.crimeFaction(in: wilderness, fromPlugin: CrimeFixture.pluginName) == nil)
    }

    /// A cell with no `XLCN` at all belongs to no location, so it answers to no
    /// crime faction either.
    @Test
    func aCellWithNoLocationLinkAnswersNone() throws {
        let resolver = try CrimeFixture.crimeFactions()
        let unlinked = try CrimeFixture.cell()

        #expect(resolver.crimeFaction(in: unlinked, fromPlugin: CrimeFixture.pluginName) == nil)
    }

    /// The location that authors the link decides it even when the link is
    /// dangling: skipping past an authored-but-unresolvable `FNAM` to a
    /// grandparent would charge the bounty to the wrong hold.
    @Test
    func anAuthoredButDanglingLinkStopsTheWalkRatherThanFallingThrough() throws {
        var data = ESMFixture.tes4()
        data += ESMFixture.topGroup("FACT", contents: CrimeFixture.faction(
            CrimeFixture.Factions.hold, "CrimeFactionHold", flags: CrimeFixture.Flags.tracksCrime
        ))
        data += ESMFixture.topGroup("LCTN", contents: [
            CrimeFixture.location(
                CrimeFixture.Locations.city, "CityLocation",
                parent: CrimeFixture.Locations.holdSeat,
                crimeFaction: 0xDEAD
            ),
            CrimeFixture.location(
                CrimeFixture.Locations.holdSeat, "HoldLocation",
                crimeFaction: CrimeFixture.Factions.hold
            )
        ].reduce(Data(), +))
        let file = try ESMFile(data: data)
        let plugins = [(CrimeFixture.pluginName, file)]
        let resolver = CrimeFactionResolver(
            locations: LocationStore(plugins: plugins),
            factions: FactionStore(plugins: plugins)
        )
        let city = try CrimeFixture.cell(location: CrimeFixture.Locations.city)

        #expect(resolver.crimeFaction(in: city, fromPlugin: CrimeFixture.pluginName) == nil)
    }
}
