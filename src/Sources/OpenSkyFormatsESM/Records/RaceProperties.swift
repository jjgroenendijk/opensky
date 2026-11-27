// RACE DATA, all 164 bytes: skill boosts, size, biped slots, movement rates,
// regen, and mount offsets. Layout and sources: docs/formats/actors.md.

import Foundation
import OpenSkyFormatsCore

/// A value per sex, in the order the record stores them.
nonisolated public struct GenderPair<Value: Equatable & Sendable>: Equatable, Sendable {
    public var male: Value
    public var female: Value

    public init(male: Value, female: Value) {
        self.male = male
        self.female = female
    }
}

/// The RACE DATA values beyond `Race.Stats` and `Race.Flags`, which hold the skill
/// boosts, flags, starting values, carry weight, mass, regeneration, and unarmed damage.
nonisolated public struct RaceProperties: Equatable, Sendable {
    /// Mount data: where a rider sits, steps off, and the camera goes.
    nonisolated public struct MountOffsets: Equatable, Sendable {
        let mount: SIMD3<Float>
        public let dismount: SIMD3<Float>
        let camera: SIMD3<Float>

        /// Where a rider steps off a race without mount data: left of the saddle, above it.
        public static let fallbackDismount = SIMD3<Float>(-50, 0, 65)
    }

    /// Two bytes xEdit leaves unnamed.
    let unknown: UInt16
    /// The height every actor of the race is drawn and moves at, per sex; 1 is the model's.
    public let height: GenderPair<Float>
    let weight: GenderPair<Float>
    public let accelerationRate: Float
    public let decelerationRate: Float
    /// 0 small, 1 medium, 2 large, 3 extra large.
    public let size: UInt32
    /// Biped slot indices, -1 for none.
    let headBipedObject: Int32
    let hairBipedObject: Int32
    public let injuredHealthPercent: Float
    let shieldBipedObject: Int32
    /// How far a bare-handed swing reaches, in world units, before the actor's scale.
    public let unarmedReach: Float
    let bodyBipedObject: Int32
    let aimAngleTolerance: Float
    let flightRadius: Float
    let angularAccelerationRate: Float
    /// Degrees: how close a turn must come to its bearing before the actor faces it.
    public let angularTolerance: Float
    /// 0x01 advanced avoidance, 0x02 non-hostile, 0x10 allow mounted combat.
    /// Optional in xEdit.
    let flags2: UInt32?
    public let mountOffsets: MountOffsets?

    init(_ reader: inout BinaryReader) throws {
        reader.skip(14) // skill boosts: Race.Stats
        unknown = try reader.readUInt16()
        height = try GenderPair(male: reader.readFloat32(), female: reader.readFloat32())
        weight = try GenderPair(male: reader.readFloat32(), female: reader.readFloat32())
        reader.skip(24) // flags, starting values, carry weight, mass: Race.Stats and Race.Flags
        accelerationRate = try reader.readFloat32()
        decelerationRate = try reader.readFloat32()
        size = try reader.readUInt32()
        headBipedObject = try reader.readInt32()
        hairBipedObject = try reader.readInt32()
        injuredHealthPercent = try reader.readFloat32()
        shieldBipedObject = try reader.readInt32()
        reader.skip(16) // regeneration and unarmed damage: Race.Stats
        unarmedReach = try reader.readFloat32()
        bodyBipedObject = try reader.readInt32()
        aimAngleTolerance = try reader.readFloat32()
        flightRadius = try reader.readFloat32()
        angularAccelerationRate = try reader.readFloat32()
        angularTolerance = try reader.readFloat32()
        flags2 = try reader.bytesRemaining >= 4 ? reader.readUInt32() : nil
        guard reader.bytesRemaining >= 36 else {
            mountOffsets = nil
            return
        }
        mountOffsets = try MountOffsets(
            mount: reader.readFloat3(), dismount: reader.readFloat3(), camera: reader.readFloat3()
        )
    }
}

/// ATKD plus its ATKE event. What each value does: docs/engine/attack-data.md.
nonisolated public struct RaceAttack: Equatable, Sendable {
    nonisolated public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let ignoreWeapon = Flags(rawValue: 0x1)
        public static let bash = Flags(rawValue: 0x2)
        public static let powerAttack = Flags(rawValue: 0x4)
        public static let leftHand = Flags(rawValue: 0x8)
        /// The hit test does not turn the cone by the attack angle.
        public static let rotating = Flags(rawValue: 0x10)
        public static let overrideData = Flags(rawValue: 0x8000_0000)
    }

    nonisolated public struct Properties: Equatable, Sendable {
        public var damageMultiplier: Float = 1
        public var attackChance: Float = 1
        /// A SPEL or SHOU.
        public var spell: FormID?
        public var flags: Flags = []
        /// Degrees added to the heading before the hit cone test.
        public var attackAngle: Float = 0
        /// The hit cone's half-angle in degrees.
        public var strikeAngle: Float = 35
        public var stagger: Float = 0
        /// A KYWD.
        public var attackType: FormID?
        public var knockdown: Float = 0
        /// Seconds before the AI picks this attack again.
        public var recoveryTime: Float = 0
        public var staminaMultiplier: Float = 1

        public init() {}

        init(_ reader: inout BinaryReader) throws {
            damageMultiplier = try reader.readFloat32()
            attackChance = try reader.readFloat32()
            spell = try reader.readFormID().nonNull
            flags = try Flags(rawValue: reader.readUInt32())
            attackAngle = try reader.readFloat32()
            strikeAngle = try reader.readFloat32()
            stagger = try reader.readFloat32()
            attackType = try reader.readFormID().nonNull
            knockdown = try reader.readFloat32()
            recoveryTime = try reader.readFloat32()
            staminaMultiplier = try reader.readFloat32()
        }
    }

    public var properties: Properties?
    /// ATKE, the animation event that starts the attack.
    public var event: String?

    public init(properties: Properties? = nil, event: String? = nil) {
        self.properties = properties
        self.event = event
    }

    /// Whether this attack starts with `name`, compared without case as the graph does.
    public func starts(with name: String) -> Bool {
        event?.caseInsensitiveCompare(name) == .orderedSame
    }
}

/// MTYP plus its optional SPED speed overrides.
nonisolated struct RaceMovementType: Equatable, Sendable {
    /// A MOVT.
    var movementType: FormID?
    /// SPED: left, right, forward, back, rotate (walk then run), then one unnamed float.
    var overrides: [Float] = []
}
