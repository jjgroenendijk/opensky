// PROJ record decoded into engine types: the thing an AMMO launches (issue
// #196, roadmap item 15.5).
//
// AMMO carries the gameplay half of an arrow — its damage, its gold value, the
// PROJ it fires — and PROJ carries the flight half. Everything the trajectory
// needs is in one 92-byte DATA struct, and the two sources agree on it
// member-for-member:
//
//   00 uint16  flags     — see `Flags` below
//   02 uint16  type      — 0x40 is an arrow; see `Kind`
//   04 float32 gravity   — a *multiplier* over the world's gravity, not an
//                          acceleration; see the note below
//   08 float32 speed     — launch speed, world units per second
//   0C float32 range     — how far it may travel before it is given up on
//   10 formID  LIGH light
//   14 formID  LIGH muzzle-flash light
//   18 float32 tracer chance
//   1C float32 explosion proximity
//   20 float32 explosion timer
//   24 formID  EXPL explosion
//   28 formID  SNDR flight sound
//   2C float32 muzzle-flash duration
//   30 float32 fade duration
//   34 float32 impact force
//   38 formID  SNDR countdown sound
//   3C formID  SNDR disable sound
//   40 formID  WEAP default weapon source
//   44 float32 cone spread
//   48 float32 collision radius
//   4C float32 lifetime
//   50 float32 relaunch interval
//   54 formID  TXST decal data   — optional
//   58 formID  COLL collision layer — optional
//
// The two trailing FormIDs are the only optional members: xEdit marks the DATA
// struct "optional from element 22", which is the decal link, so a payload of
// 84 bytes is as valid as the full 92. That is why this decoder reads what the
// payload actually carries rather than demanding one size — and why it accepts
// anything from 16 bytes (flags through range, which is the whole flight
// model) upward instead of throwing on a short DATA a mod may well have
// written.
//
// UESP prints one member this file spells differently: it calls offset 0x3C
// "uint32 always 0" where xEdit names it `Sound - Disable`, a SNDR link. The
// offsets are identical either way, so nothing downstream shifts; xEdit's
// reading is the one carried here because "always 0" is an observation about
// vanilla data rather than a statement about the field, and a mod that sets it
// would make UESP's reading wrong while leaving xEdit's right.
//
// ## `gravity` is a multiplier, and that is a measurement
//
// Neither source says what unit `gravity` is in. It is settled by reading the
// install rather than by assuming. Censusing the 134 PROJ records in
// `Skyrim.esm` by DATA `type` (2026-08-07, `openskycli archery --census`) gives,
// for the 20 of type `arrow`:
//
//     gravity  min 0.000  max 0.350  mean 0.332   (19 of 20 non-zero, all <= 1)
//     speed    min 1000   max 15000  mean 3960
//
// A member bounded by one, sitting beside a member in the thousands, is a
// dimensionless scale and not an acceleration in units per second squared. The
// arithmetic says the same thing outright: the vanilla iron arrow
// (`ArrowIronProjectile`, speed 3600, gravity 0.350) drops 18.9 world units
// over 1,000 units of level flight on the multiplier reading and 0.0135 units
// on the acceleration reading — the second is no drop at all, and a shipped
// record does not carry a member that does nothing on every projectile it has.
//
// The whole-set figures do *not* show this and are worth stating so nobody
// re-derives the wrong conclusion from them: a handful of `missile` records
// carry gravity values into the thousands, so lumping every type together
// gives a mean of 149 and hides the band the arrows are actually in. The
// finding is about arrows, and it is recorded per type in docs/engine/archery.md
// and pinned by `ProjectileRealDataTests`.
//
// So `ProjectileFlight` multiplies it by the engine's own world gravity. The
// decoder itself takes no position: it reports the float the record carries and
// names it `gravityFactor` so no caller can mistake it for an acceleration.
//
// Skipped: FULL, DEST destruction data, NAM1/NAM2 muzzle-flash model, and the
// DATA members above that only an explosive or beam projectile reads — tracer
// chance, the two explosion timings, cone spread, the muzzle and fade
// durations, the two light links and the default weapon source. A field this
// decoder does not read cannot go stale against the spec, which is the same
// rule `Impact` follows.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/PROJ"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/PROJ
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(PROJ, ...)` line
//     5449 — the DATA struct at 5454 carries the member offsets in its own
//     comments, and its trailing `22` is the "optional from element" index
//     that makes the two decal/collision links skippable.
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct Projectile: Equatable, Sendable {
    /// DATA flags. Only the ones an arrow can meaningfully set are named; the
    /// rest are carried in `rawValue` so a readout can print them.
    struct Flags: OptionSet, Equatable, Sendable {
        let rawValue: UInt16

        /// Travels instantly along a line rather than flying. Vanilla sets it
        /// on nothing an arrow fires, and the flight model refuses to
        /// integrate one.
        static let hitscan = Flags(rawValue: 0x0001)
        static let explosion = Flags(rawValue: 0x0002)
        static let alternateTrigger = Flags(rawValue: 0x0004)
        static let muzzleFlash = Flags(rawValue: 0x0008)
        static let canBeDisabled = Flags(rawValue: 0x0020)
        /// The projectile survives its impact as a pickup — what makes a spent
        /// arrow retrievable.
        static let canBePickedUp = Flags(rawValue: 0x0040)
        static let supersonic = Flags(rawValue: 0x0080)
        static let pinsLimbs = Flags(rawValue: 0x0100)
        static let passThroughSmallTransparent = Flags(rawValue: 0x0200)
        static let disableCombatAimCorrection = Flags(rawValue: 0x0400)
        /// xEdit names bit 11 `Rotation`; UESP's table stops at bit 10.
        static let rotation = Flags(rawValue: 0x0800)
    }

    /// DATA type. Written as a bit value rather than an ordinal, but vanilla
    /// sets exactly one bit per record, so it decodes as a closed enum and an
    /// unrecognized value decodes as nil rather than being forced.
    enum Kind: UInt16, Equatable, Sendable, CaseIterable {
        case missile = 0x01
        case lobber = 0x02
        case beam = 0x04
        case flame = 0x08
        case cone = 0x10
        case barrier = 0x20
        case arrow = 0x40
    }

    let formID: FormID
    let editorID: String?
    let bounds: ObjectBounds?
    /// MODL — the flying model, relative to `Data/`. What a stuck arrow is
    /// drawn from.
    let modelPath: String?

    let flags: Flags
    /// DATA type; nil when the record names a value outside the documented set.
    let kind: Kind?
    /// DATA gravity, which is a dimensionless multiplier over world gravity and
    /// not an acceleration. See the file comment.
    let gravityFactor: Float
    /// DATA launch speed, world units per second.
    let speed: Float
    /// DATA range: the travel past which the projectile is given up on, world
    /// units. Zero on records that do not bound their flight.
    let range: Float
    /// DATA impact force, which is what a hit pushes a dynamic body with.
    let impactForce: Float
    /// DATA collision radius, world units. Zero on records that fly as a point.
    let collisionRadius: Float
    /// DATA lifetime in seconds, the hard cap beside `range`. Zero where the
    /// record sets none.
    let lifetime: Float
    /// DATA — SNDR played while in flight; nil when unset or null.
    let sound: FormID?
    /// DATA — SNDR played when the projectile is disabled; nil when unset.
    let disableSound: FormID?
    /// DATA — EXPL detonated on impact; nil on an ordinary arrow. Explosive
    /// projectiles are out of item 15.5's scope, but the link is decoded so
    /// nothing has to guess whether a projectile is one.
    let explosion: FormID?
    /// DATA +0x58 — COLL collision layer. The owning plugin is needed to
    /// resolve it; `CollisionLayerStore.collisionLayer(for:fromPlugin:)`
    /// exposes the resolved record.
    let collisionLayer: FormID?
    /// VNAM — how loud firing this is for detection purposes; nil when absent.
    let soundLevel: SoundLevel?

    /// VNAM detection level, in the order UESP lists it.
    enum SoundLevel: UInt32, Equatable, Sendable, CaseIterable {
        case loud = 0
        case normal = 1
        case silent = 2
        case veryLoud = 3
    }

    /// Whether this record is one an arrow's flight model can integrate: it
    /// flies rather than tracing a line, and it has a launch speed.
    var isBallistic: Bool {
        !flags.contains(.hitscan) && speed.isFinite && speed > 0
    }

    init(record: ESMRecord) throws {
        guard record.type == "PROJ" else {
            throw ESMError.malformed("expected PROJ record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var bounds: ObjectBounds?
        var modelPath: String?
        var data = ProjectileData()
        var soundLevel: SoundLevel?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "OBND":
                bounds = try ObjectBounds(field: field)
            case "MODL":
                modelPath = try reader.readZString()
            case "DATA":
                data = try ProjectileData(field: field)
            case "VNAM":
                guard field.data.count >= 4 else { break }
                soundLevel = try SoundLevel(rawValue: reader.readUInt32())
            default:
                break
            }
        }
        self.editorID = editorID
        self.bounds = bounds
        self.modelPath = modelPath
        self.soundLevel = soundLevel
        flags = data.flags
        kind = data.kind
        gravityFactor = data.gravityFactor
        speed = data.speed
        range = data.range
        impactForce = data.impactForce
        collisionRadius = data.collisionRadius
        lifetime = data.lifetime
        sound = data.sound
        disableSound = data.disableSound
        explosion = data.explosion
        collisionLayer = data.collisionLayer
    }

    /// Test seam: a record's decoded values without a file behind them.
    init(
        formID: FormID,
        editorID: String? = nil,
        flags: Flags = [],
        kind: Kind? = .arrow,
        gravityFactor: Float,
        speed: Float,
        range: Float,
        impactForce: Float = 0,
        collisionRadius: Float = 0,
        lifetime: Float = 0,
        sound: FormID? = nil,
        collisionLayer: FormID? = nil,
        modelPath: String? = nil
    ) {
        self.formID = formID
        self.editorID = editorID
        bounds = nil
        self.modelPath = modelPath
        self.flags = flags
        self.kind = kind
        self.gravityFactor = gravityFactor
        self.speed = speed
        self.range = range
        self.impactForce = impactForce
        self.collisionRadius = collisionRadius
        self.lifetime = lifetime
        self.sound = sound
        disableSound = nil
        explosion = nil
        self.collisionLayer = collisionLayer
        soundLevel = nil
    }

    /// DATA decode kept out of `init` so the field switch stays inside the
    /// strict-lint complexity cap.
    ///
    /// Every member past the flight model is read only when the payload is
    /// long enough to carry it, so a truncated or mod-shortened DATA costs the
    /// members it does not reach and nothing else. Vanilla writes 92 bytes.
    private struct ProjectileData {
        /// Flags through `range`: `0x00` to `0x0F` inclusive, which is the
        /// members the flight model cannot do without and the shortest payload
        /// this decoder accepts.
        static let flightModelSize = 0x10

        var flags = Flags()
        var kind: Kind?
        var gravityFactor: Float = 0
        var speed: Float = 0
        var range: Float = 0
        var impactForce: Float = 0
        var collisionRadius: Float = 0
        var lifetime: Float = 0
        var sound: FormID?
        var disableSound: FormID?
        var explosion: FormID?
        var collisionLayer: FormID?

        init() {}

        init(field: ESMField) throws {
            let size = field.data.count
            guard size >= Self.flightModelSize else {
                throw ESMError.malformed(
                    "PROJ DATA has \(size) bytes, expected at least "
                        + "\(Self.flightModelSize) (flags through range)"
                )
            }
            var reader = BinaryReader(field.data)
            flags = try Flags(rawValue: reader.readUInt16())
            kind = try Kind(rawValue: reader.readUInt16())
            gravityFactor = try reader.readFloat32()
            speed = try reader.readFloat32()
            range = try reader.readFloat32()
            guard size >= 0x50 else { return }
            // 0x10 light, 0x14 muzzle-flash light, 0x18 tracer chance,
            // 0x1C/0x20 the explosion timings: all skipped, and skipped by
            // seeking rather than by reading, so a member this decoder does
            // not want cannot be misread on the way past.
            reader.seek(to: 0x24)
            explosion = try Self.link(&reader)
            sound = try Self.link(&reader)
            // 0x2C muzzle-flash duration, 0x30 fade duration.
            reader.seek(to: 0x34)
            impactForce = try reader.readFloat32()
            // 0x38 countdown sound.
            reader.seek(to: 0x3C)
            disableSound = try Self.link(&reader)
            // 0x40 default weapon source, 0x44 cone spread.
            reader.seek(to: 0x48)
            collisionRadius = try reader.readFloat32()
            lifetime = try reader.readFloat32()
            guard size >= 0x5C else { return }
            // 0x50 relaunch interval and 0x54 decal data.
            reader.seek(to: 0x58)
            collisionLayer = try Self.link(&reader)
        }

        /// One FormID member, reported as nil when null.
        private static func link(_ reader: inout BinaryReader) throws -> FormID? {
            let id = try FormID(reader.readUInt32())
            return id.isNull ? nil : id
        }
    }
}
