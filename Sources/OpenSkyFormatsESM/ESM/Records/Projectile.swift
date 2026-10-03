// PROJ record: the flight half of an arrow. AMMO holds the gameplay half.
// It decodes only the DATA members an arrow reads, and accepts a DATA of 16 bytes
// or more. `gravityFactor` scales world gravity; it is not an acceleration.
// Layout documented in docs/formats/projectiles.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Projectile: Equatable, Sendable {
    /// DATA flags. Only the ones an arrow can meaningfully set are named; the
    /// rest are carried in `rawValue` so a readout can print them.
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt16

        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        /// Travels instantly along a line rather than flying. Vanilla sets it
        /// on nothing an arrow fires, and the flight model refuses to
        /// integrate one.
        public static let hitscan = Flags(rawValue: 0x0001)
        public static let explosion = Flags(rawValue: 0x0002)
        public static let alternateTrigger = Flags(rawValue: 0x0004)
        public static let muzzleFlash = Flags(rawValue: 0x0008)
        public static let canBeDisabled = Flags(rawValue: 0x0020)
        /// The projectile survives its impact as a pickup — what makes a spent
        /// arrow retrievable.
        public static let canBePickedUp = Flags(rawValue: 0x0040)
        public static let supersonic = Flags(rawValue: 0x0080)
        public static let pinsLimbs = Flags(rawValue: 0x0100)
        public static let passThroughSmallTransparent = Flags(rawValue: 0x0200)
        public static let disableCombatAimCorrection = Flags(rawValue: 0x0400)
        /// xEdit names bit 11 `Rotation`; UESP's table stops at bit 10.
        public static let rotation = Flags(rawValue: 0x0800)
    }

    /// DATA type. Written as a bit value rather than an ordinal, but vanilla
    /// sets exactly one bit per record, so it decodes as a closed enum and an
    /// unrecognized value decodes as nil rather than being forced.
    public enum Kind: UInt16, Equatable, Sendable, CaseIterable {
        case missile = 0x01
        case lobber = 0x02
        case beam = 0x04
        case flame = 0x08
        case cone = 0x10
        case barrier = 0x20
        case arrow = 0x40
    }

    public let formID: FormID
    public let editorID: String?
    public let bounds: ObjectBounds?
    /// MODL — the flying model, relative to `Data/`. What a stuck arrow is
    /// drawn from.
    public let modelPath: String?

    public let flags: Flags
    /// DATA type; nil when the record names a value outside the documented set.
    public let kind: Kind?
    /// DATA gravity, which is a dimensionless multiplier over world gravity and
    /// not an acceleration. See the file comment.
    public let gravityFactor: Float
    /// DATA launch speed, world units per second.
    public let speed: Float
    /// DATA range: the travel past which the projectile is given up on, world
    /// units. Zero on records that do not bound their flight.
    public let range: Float
    /// DATA impact force, which is what a hit pushes a dynamic body with.
    public let impactForce: Float
    /// DATA collision radius, world units. Zero on records that fly as a point.
    public let collisionRadius: Float
    /// DATA lifetime in seconds, the hard cap beside `range`. Zero where the
    /// record sets none.
    public let lifetime: Float
    /// DATA — SNDR played while in flight; nil when unset or null.
    public let sound: FormID?
    /// DATA — SNDR played when the projectile is disabled; nil when unset.
    public let disableSound: FormID?
    /// DATA — EXPL detonated on impact; nil on an ordinary arrow. The link is
    /// decoded so nothing has to guess whether a projectile explodes.
    public let explosion: FormID?
    /// DATA +0x1C — with `alternateTrigger`, the distance to an actor that detonates it.
    public let explosionProximity: Float
    /// DATA +0x20 — with `alternateTrigger`, the seconds of flight that detonate it.
    public let explosionTimer: Float
    /// DATA +0x58 — COLL collision layer. The owning plugin is needed to
    /// resolve it; `CollisionLayerStore.collisionLayer(for:fromPlugin:)`
    /// exposes the resolved record.
    public let collisionLayer: FormID?
    /// VNAM — how loud firing this is for detection purposes; nil when absent.
    public let soundLevel: SoundLevel?

    /// VNAM detection level, in the order UESP lists it.
    public enum SoundLevel: UInt32, Equatable, Sendable, CaseIterable {
        case loud = 0
        case normal = 1
        case silent = 2
        case veryLoud = 3
    }

    /// Whether this record is one an arrow's flight model can integrate: it
    /// flies rather than tracing a line, and it has a launch speed.
    public var isBallistic: Bool {
        !flags.contains(.hitscan) && speed.isFinite && speed > 0
    }

    public init(record: ESMRecord) throws {
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
        explosionProximity = data.explosionProximity
        explosionTimer = data.explosionTimer
        collisionLayer = data.collisionLayer
    }

    /// Test seam: a record's decoded values without a file behind them.
    public init(
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
        modelPath: String? = nil,
        explosion: FormID? = nil
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
        self.explosion = explosion
        explosionProximity = 0
        explosionTimer = 0
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
        var explosionProximity: Float = 0
        var explosionTimer: Float = 0
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
            // 0x10 light, 0x14 muzzle-flash light, 0x18 tracer chance: skipped
            // by seeking, so a member this decoder does not want cannot be
            // misread on the way past.
            reader.seek(to: 0x1C)
            explosionProximity = try reader.readFloat32()
            explosionTimer = try reader.readFloat32()
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
