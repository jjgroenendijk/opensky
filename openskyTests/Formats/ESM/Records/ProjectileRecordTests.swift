// PROJ decode (issue #196, roadmap item 15.5, scope point 1).
//
// Fixtures are built in code from the published layout — never extracted game
// files (AGENTS.md "Legal & IP boundary"). Layout: UESP "Skyrim Mod:Mod File
// Format/PROJ", cross-checked against xEdit dev-4.1.6
// Core/wbDefinitionsTES5.pas `wbRecord(PROJ, ...)` line 5449. See
// docs/formats/records.md.

import Foundation
@testable import opensky
import Testing

struct ProjectileRecordTests {
    /// The full 92-byte DATA every vanilla PROJ writes.
    private static func dataField(
        flags: UInt16 = 0,
        kind: UInt16 = 0x40,
        gravity: Float = 0.35,
        speed: Float = 3600,
        range: Float = 60000,
        explosion: UInt32 = 0,
        sound: UInt32 = 0,
        impactForce: Float = 0,
        disableSound: UInt32 = 0,
        collisionRadius: Float = 0,
        lifetime: Float = 0,
        trailing: Bool = true
    ) -> Data {
        var data = Data()
        data.appendUInt16(flags)
        data.appendUInt16(kind)
        data.appendUInt32(gravity.bitPattern)
        data.appendUInt32(speed.bitPattern)
        data.appendUInt32(range.bitPattern)
        data.appendUInt32(0x0001_0000) // 0x10 light
        data.appendUInt32(0x0001_0001) // 0x14 muzzle-flash light
        data.appendUInt32(Float(0.5).bitPattern) // 0x18 tracer chance
        data.appendUInt32(Float(1).bitPattern) // 0x1C explosion proximity
        data.appendUInt32(Float(2).bitPattern) // 0x20 explosion timer
        data.appendUInt32(explosion) // 0x24
        data.appendUInt32(sound) // 0x28
        data.appendUInt32(Float(3).bitPattern) // 0x2C muzzle duration
        data.appendUInt32(Float(4).bitPattern) // 0x30 fade duration
        data.appendUInt32(impactForce.bitPattern) // 0x34
        data.appendUInt32(0x0002_0000) // 0x38 countdown sound
        data.appendUInt32(disableSound) // 0x3C
        data.appendUInt32(0x0003_0000) // 0x40 default weapon source
        data.appendUInt32(Float(5).bitPattern) // 0x44 cone spread
        data.appendUInt32(collisionRadius.bitPattern) // 0x48
        data.appendUInt32(lifetime.bitPattern) // 0x4C
        data.appendUInt32(Float(6).bitPattern) // 0x50 relaunch interval
        if trailing {
            data.appendUInt32(0x0004_0000) // 0x54 decal data
            data.appendUInt32(0x0005_0000) // 0x58 collision layer
        }
        return ESMFixture.field("DATA", data)
    }

    private static func record(
        editorID: String = "ArrowTestProjectile",
        modelPath: String? = "Weapons\\Iron\\ArrowProjectile.nif",
        soundLevel: UInt32? = 1,
        data: Data
    ) throws -> Projectile {
        var fields = ESMFixture.field("EDID", Data((editorID + "\0").utf8))
        fields += ESMFixture.field("OBND", InventoryFixture.boundsData())
        if let modelPath {
            fields += ESMFixture.field("MODL", Data((modelPath + "\0").utf8))
        }
        fields += data
        if let soundLevel {
            var payload = Data()
            payload.appendUInt32(soundLevel)
            fields += ESMFixture.field("VNAM", payload)
        }
        return try Projectile(
            record: InventoryFixture.record(
                ESMFixture.record("PROJ", formID: 0x0010_0FB1, data: fields)
            )
        )
    }

    @Test func fullDataDecodesEveryMemberTheFlightModelReads() throws {
        let projectile = try Self.record(
            data: Self.dataField(
                flags: 0x0040,
                explosion: 0x0006_0000,
                sound: 0x0007_0000,
                impactForce: 12.5,
                disableSound: 0x0008_0000,
                collisionRadius: 3,
                lifetime: 10
            )
        )

        #expect(projectile.formID.rawValue == 0x0010_0FB1)
        #expect(projectile.editorID == "ArrowTestProjectile")
        #expect(projectile.modelPath == "Weapons\\Iron\\ArrowProjectile.nif")
        #expect(projectile.kind == .arrow)
        #expect(projectile.flags.contains(.canBePickedUp))
        #expect(projectile.flags.contains(.hitscan) == false)
        #expect(projectile.gravityFactor == 0.35)
        #expect(projectile.speed == 3600)
        #expect(projectile.range == 60000)
        #expect(projectile.impactForce == 12.5)
        #expect(projectile.collisionRadius == 3)
        #expect(projectile.lifetime == 10)
        #expect(projectile.explosion?.rawValue == 0x0006_0000)
        #expect(projectile.sound?.rawValue == 0x0007_0000)
        #expect(projectile.disableSound?.rawValue == 0x0008_0000)
        #expect(projectile.collisionLayer?.rawValue == 0x0005_0000)
        #expect(projectile.soundLevel == .normal)
        #expect(projectile.bounds?.isEmpty == false)
        #expect(projectile.isBallistic)
    }

    /// xEdit marks the DATA struct "optional from element 22", which is the
    /// decal link, so an 84-byte payload is as valid as the full 92.
    @Test func the84ByteDataWithoutTheTrailingLinksIsAccepted() throws {
        let projectile = try Self.record(
            data: Self.dataField(collisionRadius: 2, lifetime: 8, trailing: false)
        )

        #expect(projectile.speed == 3600)
        #expect(projectile.collisionRadius == 2)
        #expect(projectile.lifetime == 8)
    }

    /// A payload carrying only flags through range — 16 bytes, `0x00` to
    /// `0x0F` — still gives the whole flight model, which is why that is the
    /// shortest size accepted.
    @Test func a16ByteDataDecodesTheFlightModelAndNothingElse() throws {
        var short = Data()
        short.appendUInt16(0)
        short.appendUInt16(0x01)
        short.appendUInt32(Float(1).bitPattern)
        short.appendUInt32(Float(1000).bitPattern)
        short.appendUInt32(Float(5000).bitPattern)

        let projectile = try Self.record(data: ESMFixture.field("DATA", short))

        #expect(projectile.kind == .missile)
        #expect(projectile.gravityFactor == 1)
        #expect(projectile.speed == 1000)
        #expect(projectile.range == 5000)
        #expect(projectile.collisionRadius == 0)
        #expect(projectile.sound == nil)
        #expect(projectile.collisionLayer == nil)
    }

    @Test func aDataShorterThanTheFlightModelThrows() {
        var truncated = Data()
        truncated.appendUInt16(0)
        truncated.appendUInt16(0x40)
        truncated.appendUInt32(Float(0.35).bitPattern)

        #expect(throws: ESMError.self) {
            try Self.record(data: ESMFixture.field("DATA", truncated))
        }
    }

    @Test func aRecordOfAnotherTypeThrows() throws {
        let fields = ESMFixture.field("EDID", Data("NotAProjectile\0".utf8))
        let record = try InventoryFixture.record(
            ESMFixture.record("AMMO", formID: 1, data: fields)
        )

        #expect(throws: ESMError.self) {
            try Projectile(record: record)
        }
    }

    /// A type value outside the documented set decodes as nil rather than
    /// being forced onto a case, which is the defensive rule for every enum
    /// read out of external data.
    @Test func anUndocumentedTypeValueDecodesAsNil() throws {
        let projectile = try Self.record(data: Self.dataField(kind: 0x0200))

        #expect(projectile.kind == nil)
        // Everything else still decodes: one unrecognized member must not cost
        // the record.
        #expect(projectile.speed == 3600)
    }

    @Test func aHitscanRecordIsNotBallistic() throws {
        let projectile = try Self.record(data: Self.dataField(flags: 0x0001))

        #expect(projectile.flags.contains(.hitscan))
        #expect(projectile.isBallistic == false)
    }

    /// A record with no MODL and no VNAM is ordinary vanilla data, not a
    /// fault: both are optional subrecords.
    @Test func absentOptionalSubrecordsDecodeAsNil() throws {
        let projectile = try Self.record(
            modelPath: nil, soundLevel: nil, data: Self.dataField()
        )

        #expect(projectile.modelPath == nil)
        #expect(projectile.soundLevel == nil)
        #expect(projectile.speed == 3600)
    }
}
