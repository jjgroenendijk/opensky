// Which faction answers for a crime in a given place. The cell's `XLCN` location
// and then its `PNAM` parents are walked, and the first `FNAM` wins. On this
// install the link sits at the hold (WhiterunHoldLocation), never the shop.
// No `FNAM` means no crime faction: a road or a dungeon belongs to nobody, so no
// default is substituted. See docs/engine/crime.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// Resolves the responsible crime faction for a place.
///
/// A value snapshot over the two stores, shaped like `OwnershipResolver`: the
/// answer is a pure function of the cell handed in.
nonisolated public struct CrimeFactionResolver: Sendable {
    public let locations: LocationStore
    public let factions: FactionStore

    /// The crime faction in force in `cell`, or nil when the location chain
    /// names none.
    ///
    /// `pluginName` is the plugin the cell's `XLCN` is spelled against, which
    /// is the plugin the cell record was read from.
    public func crimeFaction(in cell: Cell, fromPlugin pluginName: String) -> ResolvedFaction? {
        guard
            let location = locations.location(containing: cell, fromPlugin: pluginName)
        else { return nil }
        return crimeFaction(of: location)
    }

    /// The same answer for a location already in hand. The first `FNAM` decides,
    /// even a dangling one, because skipping it would charge the wrong hold.
    public func crimeFaction(of location: ResolvedLocation) -> ResolvedFaction? {
        for step in locations.parentChain(of: location.id) {
            guard let link = step.location.crimeFaction, !link.isNull else { continue }
            return factions.resolve(link, fromPlugin: step.sourcePlugin)
        }
        return nil
    }

    /// The same answer as the runtime identity the crime ledger is keyed by.
    public func crimeFactionKey(in cell: Cell, fromPlugin pluginName: String) -> ReferenceKey? {
        crimeFaction(in: cell, fromPlugin: pluginName).map { ReferenceKey(resolved: $0.id) }
    }

    public init(locations: LocationStore, factions: FactionStore) {
        self.locations = locations
        self.factions = factions
    }
}
