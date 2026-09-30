// Synthetic crime factions, locations, and cells, built from `FactionFixture`
// and docs/formats/factions.md. One plugin holds FACT, LCTN, and KYWD, because
// the crime runtime joins them by `ReferenceKey`. The `CRVA` defaults match
// UESP's bounty table (<https://en.uesp.net/wiki/Skyrim:Crime>), so a wrong
// sum reads as a wrong bounty.

@testable import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyCrimeInterface
@testable import OpenSkyFactionsInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorldState

public enum CrimeFixture {
    public static let pluginName = "Base.esm"

    /// FormIDs the suites name. Factions low, locations mid, actor bases high,
    /// so a mistaken swap shows up as an unresolved link rather than as a wrong
    /// answer.
    public enum Factions {
        /// Tracks crime and prices all four kinds.
        public static let hold: UInt32 = 0x10
        /// Tracks crime but ignores stealing.
        public static let tolerant: UInt32 = 0x11
        /// Owns property and does not track crime at all.
        public static let shopkeepers: UInt32 = 0x12
        /// What the `GFAC` default object names: membership makes a guard.
        public static let guards: UInt32 = 0x13
    }

    /// The hold's jail links: a `STOL` evidence chest and a
    /// `JAIL` exterior marker. Placed-reference FormIDs, so they sit apart
    /// from every record the fixture actually carries.
    public enum Links {
        public static let evidenceChest: UInt32 = 0x700
        public static let jailMarker: UInt32 = 0x701
    }

    /// The `DOBJ` record's own FormID.
    public static let defaultObjects: UInt32 = 0x31

    public enum Locations {
        public static let shop: UInt32 = 0x100
        public static let city: UInt32 = 0x101
        public static let holdSeat: UInt32 = 0x102
        /// A place whose whole chain names no crime faction.
        public static let wilderness: UInt32 = 0x103
    }

    public enum Actors {
        public static let shopkeeper: UInt32 = 0x600
        public static let resident: UInt32 = 0x601
    }

    /// `Faction.Flags` raw values the fixture composes from, spelled out so a
    /// suite reads as the behaviour it is pinning.
    public enum Flags {
        public static let tracksCrime = Faction.Flags.trackCrime.rawValue
        public static let canBeOwner = Faction.Flags.canBeOwner.rawValue
        public static let ignoresStealing = Faction.Flags.ignoreStealing.rawValue
        public static let doesNotReportAgainstMembers =
            Faction.Flags.doNotReportCrimesAgainstMembers.rawValue
    }

    public static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: pluginName.lowercased(), objectID: objectID)
    }

    public static func id(_ objectID: UInt32) -> ResolvedFormID {
        ResolvedFormID(plugin: pluginName, objectID: objectID)
    }

    // MARK: - The load order

    /// The default load order the suites run against: three factions and a
    /// four-step location chain whose crime faction is authored at the hold,
    /// exactly as `WhiterunHoldLocation` authors Whiterun's.
    public static func file() throws -> ESMFile {
        var data = ESMFixture.tes4()
        data += ESMFixture.topGroup("FACT", contents: [
            faction(
                Factions.hold,
                "CrimeFactionHold",
                flags: Flags.tracksCrime | Flags.canBeOwner,
                links: FactionFixture.link("JAIL", Links.jailMarker)
                    + FactionFixture.link("STOL", Links.evidenceChest)
            ),
            faction(
                Factions.tolerant,
                "CrimeFactionTolerant",
                flags: Flags.tracksCrime | Flags.ignoresStealing
                    | Flags.doesNotReportAgainstMembers
            ),
            faction(Factions.shopkeepers, "ShopkeeperFaction", flags: Flags.canBeOwner),
            FactionFixture.record(formID: Factions.guards, editorID: "GuardFaction")
        ].reduce(Data(), +))
        data += ESMFixture.topGroup("LCTN", contents: [
            location(Locations.shop, "ShopLocation", parent: Locations.city),
            location(Locations.city, "CityLocation", parent: Locations.holdSeat),
            location(Locations.holdSeat, "HoldLocation", crimeFaction: Factions.hold),
            location(Locations.wilderness, "WildernessLocation")
        ].reduce(Data(), +))
        data += ESMFixture.topGroup("DOBJ", contents: defaultObjectsRecord())
        return try ESMFile(data: data)
    }

    public static func factionStore() throws -> FactionStore {
        try FactionStore(plugins: [(pluginName, file())])
    }

    public static func locationStore() throws -> LocationStore {
        try LocationStore(plugins: [(pluginName, file())])
    }

    // MARK: - Records

    /// One FACT with a `CRVA` block, the flags given, and any link fields.
    public static func faction(
        _ formID: UInt32,
        _ editorID: String,
        flags: UInt32,
        crimeValues: Data? = nil,
        links: Data = Data()
    ) -> Data {
        FactionFixture.record(
            formID: formID,
            editorID: editorID,
            body: FactionFixture.flags(flags)
                + links
                + (crimeValues ?? FactionFixture.crimeValues())
        )
    }

    /// The `DOBJ` naming the guard faction under `GFAC`, laid out as a run of
    /// four-character tag and FormID pairs (docs/formats/records.md).
    public static func defaultObjectsRecord() -> Data {
        var defaults = Data("GFAC".utf8)
        defaults.appendUInt32(Factions.guards)
        return ESMFixture.record(
            "DOBJ",
            formID: defaultObjects,
            data: ESMFixture.field("DNAM", defaults)
        )
    }

    /// One LCTN, optionally naming a parent and a crime faction (`FNAM`).
    public static func location(
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
    public static func cell(
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
    public static func player(memberships: [(faction: UInt32, rank: Int8)] = []) -> CrimeActor {
        CrimeActor(base: nil, memberships: state(memberships))
    }

    /// One NPC by its base record, optionally in factions.
    public static func actor(
        base: UInt32,
        memberships: [(faction: UInt32, rank: Int8)] = []
    ) -> CrimeActor {
        CrimeActor(base: key(base), memberships: state(memberships))
    }

    public static func state(_ memberships: [(faction: UInt32, rank: Int8)]) -> ActorFactionState {
        ActorFactionState(memberships: memberships.map {
            ActorFactionMembership(faction: key($0.faction), rank: $0.rank)
        })
    }

    /// One crime against the hold, witnessed or not.
    public static func event(
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
}
