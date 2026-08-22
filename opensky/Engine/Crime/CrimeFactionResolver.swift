// Which faction answers for a crime committed in a given place (issue #504,
// roadmap item 21.5).
//
// ## The chain
//
// A cell names its location with `XLCN`, a location names its crime faction
// with `FNAM`, and almost no location names one. The link is authored at the
// hold, and everything inside the hold inherits it by walking `PNAM` upwards.
// Observed on this install, which is what fixed the rule rather than memory:
//
//   WhiterunBelethorsGeneralGoodsLocation  PNAM -> WhiterunLocation   (no FNAM)
//   WhiterunLocation                       PNAM -> WhiterunHoldLocation
//   WhiterunHoldLocation                   FNAM  (the crime faction)
//
// So the resolution is: the cell's own location, then its parents in order, and
// the first `FNAM` found wins. UESP describes the same shape from the player's
// side — "Bounties are tracked separately for each of Skyrim's nine holds and
// you will only incur a bounty in the hold in which you commit a crime"
// (<https://en.uesp.net/wiki/Skyrim:Crime>).
//
// A chain that ends without an `FNAM` has no crime faction, and that is a real
// answer rather than a gap: a dungeon and a stretch of road belong to nobody,
// which is why killing a bandit on the road costs nothing. Nothing here
// substitutes a default faction, because substituting one would put a bounty
// where the data says there is none.
//
// The walk itself is `LocationStore.parentChain(of:)`, which already bounds a
// malformed `PNAM` cycle with a visited set, so nothing here re-implements it.
//
// Documented in docs/engine/crime.md.

import Foundation

/// Resolves the responsible crime faction for a place.
///
/// A value snapshot over the two stores, shaped like `OwnershipResolver`: the
/// answer is a pure function of the cell handed in.
nonisolated struct CrimeFactionResolver {
    let locations: LocationStore
    let factions: FactionStore

    /// The crime faction in force in `cell`, or nil when the location chain
    /// names none.
    ///
    /// `pluginName` is the plugin the cell's `XLCN` is spelled against, which
    /// is the plugin the cell record was read from.
    func crimeFaction(in cell: Cell, fromPlugin pluginName: String) -> ResolvedFaction? {
        guard
            let location = locations.location(containing: cell, fromPlugin: pluginName)
        else { return nil }
        return crimeFaction(of: location)
    }

    /// The same answer for a location already in hand, walking its parents.
    ///
    /// The first location in the chain that authors an `FNAM` decides it, even
    /// when that `FNAM` names a record this load order no longer carries: an
    /// authored-but-dangling link is a place that *has* an owner the engine
    /// cannot name, and skipping past it to a grandparent would charge the
    /// bounty to the wrong hold.
    func crimeFaction(of location: ResolvedLocation) -> ResolvedFaction? {
        for step in locations.parentChain(of: location.id) {
            guard let link = step.location.crimeFaction, !link.isNull else { continue }
            return factions.resolve(link, fromPlugin: step.sourcePlugin)
        }
        return nil
    }

    /// The same answer as the runtime identity the crime ledger is keyed by.
    func crimeFactionKey(in cell: Cell, fromPlugin pluginName: String) -> ReferenceKey? {
        crimeFaction(in: cell, fromPlugin: pluginName).map { ReferenceKey(resolved: $0.id) }
    }
}
