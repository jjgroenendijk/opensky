// Synthetic subrecord payloads for the inventory record tests, built from the
// published layouts. Layout: docs/formats/item-records.md.

import Foundation
@testable import OpenSkyFormatsESM

public enum InventoryFixture: Sendable {
    /// Parses fixture bytes back into the single record they encode.
    public static func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    public static func formIDField(_ type: String, _ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return ESMFixture.field(type, data)
    }

    public static func keywordFields(_ keywords: [UInt32]) -> Data {
        var count = Data()
        count.appendUInt32(UInt32(keywords.count))
        var payload = Data()
        for keyword in keywords {
            payload.appendUInt32(keyword)
        }
        return ESMFixture.field("KSIZ", count) + ESMFixture.field("KWDA", payload)
    }

    /// OBND: six int16, (-2,-2,-2) to (2,2,2).
    public static func boundsData() -> Data {
        var data = Data()
        for value: Int16 in [-2, -2, -2, 2, 2, 2] {
            data.appendUInt16(UInt16(bitPattern: value))
        }
        return data
    }

    /// The 8-byte value+weight DATA shared by MISC, INGR and ARMO.
    public static func valueWeightData(value: Int32, weight: Float) -> Data {
        var data = Data()
        data.appendUInt32(UInt32(bitPattern: value))
        data.appendUInt32(weight.bitPattern)
        return data
    }

    /// BOOK DATA: flags, type, 2 unused, teaches union, value, weight.
    public static func bookData(
        flags: UInt8, kind: UInt8, teaches: UInt32, value: Int32, weight: Float
    ) -> Data {
        var data = Data([flags, kind, 0, 0])
        data.appendUInt32(teaches)
        data.appendUInt32(UInt32(bitPattern: value))
        data.appendUInt32(weight.bitPattern)
        return data
    }

    /// ALCH ENIT: value, flags, addiction, addiction chance, consume sound.
    public static func enitData(value: Int32, flags: UInt32, addictionChance: Float = 0) -> Data {
        var data = Data()
        data.appendUInt32(UInt32(bitPattern: value))
        data.appendUInt32(flags)
        data.appendUInt32(0) // addiction
        data.appendUInt32(addictionChance.bitPattern)
        data.appendUInt32(0x0002_0000) // consume sound
        return data
    }

    public static func effectFields(
        effect: UInt32, magnitude: Float, area: UInt32, duration: UInt32
    ) -> Data {
        var efit = Data()
        efit.appendUInt32(magnitude.bitPattern)
        efit.appendUInt32(area)
        efit.appendUInt32(duration)
        return formIDField("EFID", effect) + ESMFixture.field("EFIT", efit)
    }

    /// WEAP DATA: uint32 value, float weight, uint16 damage.
    public static func weaponData(value: Int32, weight: Float, damage: UInt16) -> Data {
        var data = valueWeightData(value: value, weight: weight)
        data.appendUInt16(damage)
        return data
    }

    /// WEAP DNAM: 100 bytes; only 0x00, 0x04, 0x08, 0x0C, 0x4C and 0x60 are
    /// read. Stagger is fixed at 0.75 so its offset is asserted too.
    /// ARMA DNAM, 12 bytes: male priority, female priority, four bytes of weight
    /// slider flags, detection sound, one unused byte, then the weapon-adjust
    /// float (UESP + xEdit; see ArmorAddon.swift).
    public static func armorAddonDNAM(male: UInt8, female: UInt8, weaponAdjust: Float = 0) -> Data {
        var data = Data([male, female, 0, 0, 0, 0, 0, 0])
        data.appendFloat32(weaponAdjust)
        return ESMFixture.field("DNAM", data)
    }

    public static func weaponDNAM(
        animation: UInt8, speed: Float, reach: Float, flags: UInt16, skill: Int32
    ) -> Data {
        var data = Data([animation, 0, 0, 0])
        data.appendUInt32(speed.bitPattern)
        data.appendUInt32(reach.bitPattern)
        data.appendUInt16(flags)
        data.append(Data(count: 0x4C - 0x0E))
        data.appendUInt32(UInt32(bitPattern: skill))
        data.append(Data(count: 0x60 - 0x50))
        data.appendUInt32(Float(0.75).bitPattern)
        return data
    }

    /// WEAP CRDT: 24 bytes in SSE (SPEL at 0x10), 16 in classic (at 0x0C).
    public static func criticalData(sse: Bool, damage: UInt16, spell: UInt32) -> Data {
        var data = Data()
        data.appendUInt16(damage)
        data.appendUInt16(0)
        data.appendUInt32(Float(1).bitPattern)
        data.append(contentsOf: [1]) // on death
        data.append(Data(count: sse ? 7 : 3))
        data.appendUInt32(spell)
        if sse {
            data.append(Data(count: 4))
        }
        return data
    }

    /// AMMO DATA: projectile, flags, damage, value, and — SSE only — weight.
    public static func ammoData(
        projectile: UInt32, flags: UInt32, damage: Float, value: Int32, weight: Float?
    ) -> Data {
        var data = Data()
        data.appendUInt32(projectile)
        data.appendUInt32(flags)
        data.appendUInt32(damage.bitPattern)
        data.appendUInt32(UInt32(bitPattern: value))
        if let weight {
            data.appendUInt32(weight.bitPattern)
        }
        return data
    }

    public static func cntoData(item: UInt32, count: Int32) -> Data {
        var data = Data()
        data.appendUInt32(item)
        data.appendUInt32(UInt32(bitPattern: count))
        return data
    }

    public static func coedData(
        owner: UInt32,
        ownerCondition: UInt32 = 0,
        condition: Float
    ) -> Data {
        var data = Data()
        data.appendUInt32(owner)
        data.appendUInt32(ownerCondition)
        data.appendUInt32(condition.bitPattern)
        return data
    }
}
