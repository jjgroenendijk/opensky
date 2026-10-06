// Decoders for the global data tables import needs: misc stats, player location,
// global variables, created objects, and weather. Layouts: docs/formats/ess.md#global-data.

import Foundation

nonisolated public struct ESSMiscStat: Equatable, Sendable {
    public let name: String
    /// 0 general, 1 quest, 2 combat, 3 magic, 4 crafting, 5 crime, 6 DLC.
    public let category: UInt8
    public let value: Int32

    public static func decodeAll(_ data: Data) throws(ESSError) -> [Self] {
        var reader = ESSReader(data)
        let count = try reader.count32("misc stats", minimumElementSize: 7)
        var stats: [Self] = []
        for _ in 0 ..< count {
            try stats.append(Self(
                name: reader.wstring("misc stat name"),
                category: reader.uint8("misc stat category"),
                value: reader.int32("misc stat value")
            ))
        }
        return stats
    }
}

nonisolated public struct ESSPlayerLocation: Equatable, Sendable {
    /// The next id the game hands a created form, `0xFF` plus this.
    public let nextObjectID: UInt32
    /// The worldspace `cell` is in, or null in an interior.
    public let worldspace: ESSRefID
    public let cell: SIMD2<Int32>
    /// A worldspace or an interior cell. `position` is in its space.
    public let space: ESSRefID
    public let position: SIMD3<Float>

    public static func decode(_ data: Data) throws(ESSError) -> Self {
        var reader = ESSReader(data)
        return try Self(
            nextObjectID: reader.uint32("next object id"),
            worldspace: reader.refID("player worldspace"),
            cell: SIMD2(reader.int32("player cell x"), reader.int32("player cell y")),
            space: reader.refID("player space"),
            position: reader.vector3("player position")
        )
    }
}

nonisolated public struct ESSGlobalVariable: Equatable, Sendable {
    public let global: ESSRefID
    public let value: Float

    public static func decodeAll(_ data: Data) throws(ESSError) -> [Self] {
        var reader = ESSReader(data)
        let count = try reader.count("global variables", minimumElementSize: 7)
        var globals: [Self] = []
        for _ in 0 ..< count {
            try globals.append(Self(
                global: reader.refID("global variable"), value: reader.float32("global value")
            ))
        }
        return globals
    }
}

nonisolated public struct ESSCreatedObject: Equatable, Sendable {
    nonisolated public enum Kind: String, CaseIterable, Sendable {
        case weaponEnchantment, armorEnchantment, potion, poison
    }

    nonisolated public struct Effect: Equatable, Sendable {
        public let effect: ESSRefID
        public let magnitude: Float
        public let duration: UInt32
        public let area: UInt32
        public let price: Float
    }

    public let kind: Kind
    public let form: ESSRefID
    public let timesUsed: UInt32
    public let effects: [Effect]

    public static func decodeAll(_ data: Data) throws(ESSError) -> [Self] {
        var reader = ESSReader(data)
        var objects: [Self] = []
        for kind in Kind.allCases {
            let count = try reader.count("created \(kind.rawValue)", minimumElementSize: 8)
            for _ in 0 ..< count {
                try objects.append(readOne(&reader, kind: kind))
            }
        }
        return objects
    }

    private static func readOne(_ reader: inout ESSReader, kind: Kind) throws(ESSError) -> Self {
        let form = try reader.refID("created object")
        let used = try reader.uint32("created object uses")
        let count = try reader.count("created object effects", minimumElementSize: 19)
        var effects: [Effect] = []
        for _ in 0 ..< count {
            try effects.append(Effect(
                effect: reader.refID("created effect"),
                magnitude: reader.float32("created effect magnitude"),
                duration: reader.uint32("created effect duration"),
                area: reader.uint32("created effect area"),
                price: reader.float32("created effect price")
            ))
        }
        return Self(kind: kind, form: form, timesUsed: used, effects: effects)
    }
}

/// The leading, documented part of the weather table. The rest is undocumented.
nonisolated public struct ESSWeather: Equatable, Sendable {
    public let climate: ESSRefID
    public let weather: ESSRefID
    /// Null outside a transition.
    public let previousWeather: ESSRefID
    public let regionWeather: ESSRefID
    /// The in-game hour.
    public let currentHour: Float
    /// How far the transition to `weather` has gone, 0 to 1.
    public let transition: Float

    public static func decode(_ data: Data) throws(ESSError) -> Self {
        var reader = ESSReader(data)
        let climate = try reader.refID("climate")
        let weather = try reader.refID("weather")
        let previous = try reader.refID("previous weather")
        _ = try reader.refID("weather 4")
        _ = try reader.refID("weather 5")
        let region = try reader.refID("region weather")
        let hour = try reader.float32("weather hour")
        _ = try reader.float32("weather start")
        let transition = try reader.float32("weather transition")
        return Self(
            climate: climate, weather: weather, previousWeather: previous,
            regionWeather: region, currentHour: hour, transition: transition
        )
    }
}

nonisolated extension ESSFile {
    public func miscStats() throws(ESSError) -> [ESSMiscStat] {
        guard let table = globalData(.miscStats) else { return [] }
        return try ESSMiscStat.decodeAll(table.data)
    }

    public func playerLocation() throws(ESSError) -> ESSPlayerLocation? {
        guard let table = globalData(.playerLocation) else { return nil }
        return try ESSPlayerLocation.decode(table.data)
    }

    public func globalVariables() throws(ESSError) -> [ESSGlobalVariable] {
        guard let table = globalData(.globalVariables) else { return [] }
        return try ESSGlobalVariable.decodeAll(table.data)
    }

    public func createdObjects() throws(ESSError) -> [ESSCreatedObject] {
        guard let table = globalData(.createdObjects) else { return [] }
        return try ESSCreatedObject.decodeAll(table.data)
    }

    public func papyrus() throws(ESSError) -> ESSPapyrus? {
        guard let table = globalData(.papyrus) else { return nil }
        return try ESSPapyrus(data: table.data)
    }

    public func weather() throws(ESSError) -> ESSWeather? {
        guard let table = globalData(.weather) else { return nil }
        return try ESSWeather.decode(table.data)
    }
}
