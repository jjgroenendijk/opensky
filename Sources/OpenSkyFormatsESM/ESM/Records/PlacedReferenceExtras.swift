// Placed-reference subrecords shared by REFR, ACHR, PHZD, and PGRE: XLOC lock
// data, XESP enable parent, and the XMRK map-marker group. Decode only; the
// runtime resolves the links. Layout and sources: docs/formats/placed-references.md.

import Foundation
import OpenSkyFormatsCore

/// XLOC lock level. An unknown byte keeps its value.
nonisolated public enum LockLevel: Equatable, Sendable {
    case novice
    case apprentice
    case adept
    case expert
    case master
    case requiresKey
    case unknown(UInt8)

    public init(rawValue: UInt8) {
        self = switch rawValue {
        case 1: .novice
        case 25: .apprentice
        case 50: .adept
        case 75: .expert
        case 100: .master
        case 255: .requiresKey
        default: .unknown(rawValue)
        }
    }

    /// The XLOC byte as written.
    public var rawValue: UInt8 {
        switch self {
        case .novice: 1
        case .apprentice: 25
        case .adept: 50
        case .expert: 75
        case .master: 100
        case .requiresKey: 255
        case let .unknown(value): value
        }
    }
}

/// XLOC: level, key, and flags. Vanilla writes 20 bytes; xEdit allows any size from 4.
nonisolated public struct LockData: Equatable, Sendable {
    public let level: LockLevel
    /// A KEYM. Nil when absent or null.
    public let key: FormID?
    public let flags: UInt8
    /// The XLOC size, for the size histogram.
    public let size: Int

    public init(level: LockLevel, key: FormID?, flags: UInt8 = 0, size: Int = 20) {
        self.level = level
        self.key = key
        self.flags = flags
        self.size = size
    }

    /// Flag bit 0x04: the level scales with the player.
    public var isLeveled: Bool {
        flags & 0x04 != 0
    }

    init(_ reader: inout BinaryReader) throws {
        size = reader.bytesRemaining
        level = try LockLevel(rawValue: reader.readUInt8())
        reader.skip(min(3, reader.bytesRemaining))
        key = reader.bytesRemaining >= 4 ? try reader.readFormID().nonNull : nil
        flags = reader.bytesRemaining >= 1 ? try reader.readUInt8() : 0
    }
}

/// XESP: the reference whose enable state this one follows.
nonisolated public struct EnableParent: Equatable, Sendable {
    public internal(set) var parent: FormID
    public let flags: UInt8

    /// Flag bit 0x01: enabled while the parent is disabled.
    public var isOppositeOfParent: Bool {
        flags & 0x01 != 0
    }

    /// Flag bit 0x02: appear without fading in.
    public var popsIn: Bool {
        flags & 0x02 != 0
    }

    init(_ reader: inout BinaryReader) throws {
        parent = try reader.readFormID()
        flags = reader.bytesRemaining >= 1 ? try reader.readUInt8() : 0
    }
}

/// TNAM marker type. Names follow xEdit's `wbMapMarkerEnum`; an unknown value keeps its number.
nonisolated public struct MapMarkerType: Equatable, Hashable, Sendable {
    private static let names = [
        "None", "City", "Town", "Settlement", "Cave", "Camp", "Fort", "Nordic Ruins",
        "Dwemer Ruin", "Shipwreck", "Grove", "Landmark", "Dragon Lair", "Farm", "Wood Mill",
        "Mine", "Imperial Camp", "Stormcloak Camp", "Doomstone", "Wheat Mill", "Smelter",
        "Stable", "Imperial Tower", "Clearing", "Pass", "Altar", "Rock", "Lighthouse",
        "Orc Stronghold", "Giant Camp", "Shack", "Nordic Tower", "Nordic Dwelling", "Docks",
        "Shrine", "Riften Castle", "Riften Capitol", "Windhelm Castle", "Windhelm Capitol",
        "Whiterun Castle", "Whiterun Capitol", "Solitude Castle", "Solitude Capitol",
        "Markarth Castle", "Markarth Capitol", "Winterhold Castle", "Winterhold Capitol",
        "Morthal Castle", "Morthal Capitol", "Falkreath Castle", "Falkreath Capitol",
        "Dawnstar Castle", "Dawnstar Capitol", "Temple of Miraak", "Raven Rock", "Beast Stone",
        "Tel Mithryn", "To Skyrim", "To Solstheim", "Castle Karstaag"
    ]

    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Nil for a value the xEdit table does not name.
    public var name: String? {
        Int(rawValue) < Self.names.count ? Self.names[Int(rawValue)] : nil
    }
}

/// The XMRK group: flags, name, and type of a map marker.
nonisolated public struct MapMarker: Equatable, Sendable {
    public let flags: UInt8
    /// FULL, kept raw: a REFR decode does not know the plugin's localized flag.
    public let nameField: Data?
    public let type: MapMarkerType?

    /// FNAM bit 0x01.
    public var isVisible: Bool {
        flags & 0x01 != 0
    }

    /// FNAM bit 0x02.
    public var canTravelTo: Bool {
        flags & 0x02 != 0
    }

    /// FNAM bit 0x04: hidden from the "show all" map cheat.
    public var isHiddenFromShowAll: Bool {
        flags & 0x04 != 0
    }

    /// FULL as display text for a plugin with the given localized flag.
    public func name(localized: Bool) -> LString? {
        guard let nameField else { return nil }
        return try? LString(field: ESMField(type: "FULL", data: nameField), localized: localized)
    }
}

/// Accumulates the shared subrecords inside a placed-reference field loop.
nonisolated struct PlacedReferenceExtras {
    var lock: LockData?
    var enableParent: EnableParent?
    var markerFlags: UInt8?
    var markerName: Data?
    var markerType: MapMarkerType?
    var hasMarker = false
    var tally = FieldTally()

    var mapMarker: MapMarker? {
        guard hasMarker else { return nil }
        return MapMarker(flags: markerFlags ?? 0, nameField: markerName, type: markerType)
    }

    /// Consumes `field` when it is a shared subrecord. A malformed one is tallied.
    mutating func decode(_ field: ESMField) -> Bool {
        var reader = BinaryReader(field.data)
        do {
            switch field.type {
            case "XLOC": lock = try LockData(&reader)
            case "XESP": enableParent = try EnableParent(&reader)
            case "XMRK": hasMarker = true
            case "FNAM": markerFlags = try reader.readUInt8()
            case "FULL": markerName = field.data
            case "TNAM": markerType = try MapMarkerType(rawValue: reader.readUInt8())
            default: return false
            }
        } catch {
            tally.note(.malformedField(field.type))
        }
        return true
    }
}
