// Synthetic crime factions, locations and cells for the crime suites (issue
// #504). Every layout comes from `FactionFixture` and the field specs in
// docs/formats/factions.md and docs/formats/records.md, so no bytes from the
// game install appear here (AGENTS.md "Legal & IP boundary").
//
// One plugin carries the FACT, LCTN and KYWD records together, because the
// crime runtime joins them: a cell's `XLCN` and a location's `FNAM` have to
// resolve to the same `ReferenceKey`s the ledger is written under, or the
// suites would be testing the fixture rather than the runtime.
//
// The `CRVA` numbers default to the ones the local install carries on
// `CrimeFactionWhiterun` — "murder 1000, assault 40, trespass 5, pickpocket 25,
// steal multiplier 0.5000" — which are also UESP's published bounty table
// (<https://en.uesp.net/wiki/Skyrim:Crime>). Using the real numbers is what
// makes an arithmetic mistake in the suites read as a wrong bounty rather than
// as a fixture nobody can check.

import Foundation
@testable import opensky

enum CrimeFixture {
    static let pluginName = "Base.esm"

    /// FormIDs the suites name. Factions low, locations mid, actor bases high,
    /// so a mistaken swap shows up as an unresolved link rather than as a wrong
    /// answer.
    enum Factions {
        /// Tracks crime and prices all four kinds.
        static let hold: UInt32 = 0x10
        /// Tracks crime but ignores stealing.
        static let tolerant: UInt32 = 0x11
        /// Owns property and does not track crime at all.
        static let shopkeepers: UInt32 = 0x12
    }

    enum Locations {
        static let shop: UInt32 = 0x100
        static let city: UInt32 = 0x101
        static let holdSeat: UInt32 = 0x102
        /// A place whose whole chain names no crime faction.
        static let wilderness: UInt32 = 0x103
    }

    enum Actors {
        static let shopkeeper: UInt32 = 0x600
        static let resident: UInt32 = 0x601
    }

    /// `Faction.Flags` raw values the fixture composes from, spelled out so a
    /// suite reads as the behaviour it is pinning.
    enum Flags {
        static let tracksCrime = Faction.Flags.trackCrime.rawValue
        static let canBeOwner = Faction.Flags.canBeOwner.rawValue
        static let ignoresStealing = Faction.Flags.ignoreStealing.rawValue
        static let doesNotReportAgainstMembers =
            Faction.Flags.doNotReportCrimesAgainstMembers.rawValue
    }

    static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: pluginName.lowercased(), objectID: objectID)
    }

    static func id(_ objectID: UInt32) -> ResolvedFormID {
        ResolvedFormID(plugin: pluginName, objectID: objectID)
    }

    // MARK: - The load order

    /// The default load order the suites run against: three factions and a
    /// four-step location chain whose crime faction is authored at the hold,
    /// exactly as `WhiterunHoldLocation` authors Whiterun's.
    static func file() throws -> ESMFile {
        var data = ESMFixture.tes4()
        data += ESMFixture.topGroup("FACT", contents: [
            faction(
                Factions.hold,
                "CrimeFactionHold",
                flags: Flags.tracksCrime | Flags.canBeOwner
            ),
            faction(
                Factions.tolerant,
                "CrimeFactionTolerant",
                flags: Flags.tracksCrime | Flags.ignoresStealing
                    | Flags.doesNotReportAgainstMembers
            ),
            faction(Factions.shopkeepers, "ShopkeeperFaction", flags: Flags.canBeOwner)
        ].reduce(Data(), +))
        data += ESMFixture.topGroup("LCTN", contents: [
            location(Locations.shop, "ShopLocation", parent: Locations.city),
            location(Locations.city, "CityLocation", parent: Locations.holdSeat),
            location(Locations.holdSeat, "HoldLocation", crimeFaction: Factions.hold),
            location(Locations.wilderness, "WildernessLocation")
        ].reduce(Data(), +))
        return try ESMFile(data: data)
    }

    static func factionStore() throws -> FactionStore {
        try FactionStore(plugins: [(pluginName, file())])
    }

    static func locationStore() throws -> LocationStore {
        try LocationStore(plugins: [(pluginName, file())])
    }

    static func crimeFactions() throws -> CrimeFactionResolver {
        try CrimeFactionResolver(locations: locationStore(), factions: factionStore())
    }

    static func ownershipResolver() throws -> OwnershipResolver {
        try OwnershipResolver(factions: factionStore(), pluginName: pluginName)
    }

    // MARK: - Records

    /// One FACT with a `CRVA` block and the flags given.
    static func faction(
        _ formID: UInt32,
        _ editorID: String,
        flags: UInt32,
        crimeValues: Data? = nil
    ) -> Data {
        FactionFixture.record(
            formID: formID,
            editorID: editorID,
            body: FactionFixture.flags(flags)
                + (crimeValues ?? FactionFixture.crimeValues())
        )
    }

    /// One LCTN, optionally naming a parent and a crime faction (`FNAM`).
    static func location(
        _ formID: UInt32,
        _ editorID: String,
        parent: UInt32? = nil,
        crimeFaction: UInt32? = nil
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        if let parent {
            fields += FactionFixture.link("PNAM", parent)
        }
        if let crimeFaction {
            fields += FactionFixture.link("FNAM", crimeFaction)
        }
        return ESMFixture.record("LCTN", formID: formID, data: fields)
    }

    /// One CELL with an optional `XLCN` link and an optional `XOWN`/`XRNK`
    /// pair — the fields ownership precedence and crime-faction resolution both
    /// read.
    static func cell(
        formID: UInt32 = 0x50,
        location: UInt32? = nil,
        owner: UInt32? = nil,
        ownerRank: Int32? = nil
    ) throws -> Cell {
        var fields = Data()
        if let location {
            fields += FactionFixture.link("XLCN", location)
        }
        if let owner {
            fields += FactionFixture.link("XOWN", owner)
        }
        if let ownerRank {
            fields += FactionFixture.link("XRNK", UInt32(bitPattern: ownerRank))
        }
        let bytes = ESMFixture.record("CELL", formID: formID, data: fields)
        return try Cell(record: FactionFixture.decode(bytes), localized: false)
    }

    // MARK: - Actors and events

    /// The player, optionally in factions.
    static func player(memberships: [(faction: UInt32, rank: Int8)] = []) -> CrimeActor {
        CrimeActor(key: .player, base: nil, memberships: state(memberships))
    }

    /// One NPC by its base record, optionally in factions.
    static func actor(
        _ reference: UInt32,
        base: UInt32,
        memberships: [(faction: UInt32, rank: Int8)] = []
    ) -> CrimeActor {
        CrimeActor(key: key(reference), base: key(base), memberships: state(memberships))
    }

    static func state(_ memberships: [(faction: UInt32, rank: Int8)]) -> ActorFactionState {
        ActorFactionState(memberships: memberships.map {
            ActorFactionMembership(faction: key($0.faction), rank: $0.rank)
        })
    }

    /// One crime against the hold, witnessed or not.
    static func event(
        _ kind: CrimeKind,
        faction: UInt32? = Factions.hold,
        victim: UInt32? = nil,
        witnessed: Bool = true,
        stolenValue: Int64 = 0
    ) -> CrimeEvent {
        CrimeEvent(
            kind: kind,
            perpetrator: .player,
            victim: victim.map(key),
            crimeFaction: faction.map(key),
            witnessed: witnessed,
            stolenValue: stolenValue
        )
    }

    /// A crime runtime over a fresh store and the fixture load order.
    @MainActor
    static func runtime(store: WorldStateStore = WorldStateStore()) throws -> CrimeRuntime {
        try CrimeRuntime(store: store, factions: factionStore())
    }
}
