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

nonisolated public struct RaceProperties: Equatable, Sendable {
    nonisolated public struct SkillBoost: Equatable, Sendable {
        /// An actor-value index, -1 for none.
        public let skill: Int8
        public let boost: Int8
    }

    /// Mount data: where a rider sits, steps off, and the camera goes.
    nonisolated public struct MountOffsets: Equatable, Sendable {
        public let mount: SIMD3<Float>
        public let dismount: SIMD3<Float>
        public let camera: SIMD3<Float>
    }

    public let skillBoosts: [SkillBoost]
    /// Two bytes xEdit leaves unnamed.
    public let unknown: UInt16
    public let height: GenderPair<Float>
    public let weight: GenderPair<Float>
    /// The flags `Race.Flags` names in part.
    public let flags: UInt32
    public let startingHealth: Float
    public let startingMagicka: Float
    public let startingStamina: Float
    public let baseCarryWeight: Float
    public let baseMass: Float
    public let accelerationRate: Float
    public let decelerationRate: Float
    /// 0 small, 1 medium, 2 large, 3 extra large.
    public let size: UInt32
    /// Biped slot indices, -1 for none.
    public let headBipedObject: Int32
    public let hairBipedObject: Int32
    public let injuredHealthPercent: Float
    public let shieldBipedObject: Int32
    public let healthRegen: Float
    public let magickaRegen: Float
    public let staminaRegen: Float
    public let unarmedDamage: Float
    public let unarmedReach: Float
    public let bodyBipedObject: Int32
    public let aimAngleTolerance: Float
    public let flightRadius: Float
    public let angularAccelerationRate: Float
    public let angularTolerance: Float
    /// 0x01 advanced avoidance, 0x02 non-hostile, 0x10 allow mounted combat.
    /// Optional in xEdit.
    public let flags2: UInt32?
    public let mountOffsets: MountOffsets?

    init(_ reader: inout BinaryReader) throws {
        skillBoosts = try (0 ..< 7).map { _ in
            try SkillBoost(skill: reader.readInt8(), boost: reader.readInt8())
        }
        unknown = try reader.readUInt16()
        height = try GenderPair(male: reader.readFloat32(), female: reader.readFloat32())
        weight = try GenderPair(male: reader.readFloat32(), female: reader.readFloat32())
        flags = try reader.readUInt32()
        startingHealth = try reader.readFloat32()
        startingMagicka = try reader.readFloat32()
        startingStamina = try reader.readFloat32()
        baseCarryWeight = try reader.readFloat32()
        baseMass = try reader.readFloat32()
        accelerationRate = try reader.readFloat32()
        decelerationRate = try reader.readFloat32()
        size = try reader.readUInt32()
        headBipedObject = try reader.readInt32()
        hairBipedObject = try reader.readInt32()
        injuredHealthPercent = try reader.readFloat32()
        shieldBipedObject = try reader.readInt32()
        healthRegen = try reader.readFloat32()
        magickaRegen = try reader.readFloat32()
        staminaRegen = try reader.readFloat32()
        unarmedDamage = try reader.readFloat32()
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

/// ATKD plus its ATKE event.
nonisolated public struct RaceAttack: Equatable, Sendable {
    nonisolated public struct Properties: Equatable, Sendable {
        public let damageMultiplier: Float
        public let attackChance: Float
        /// A SPEL or SHOU.
        public let spell: FormID?
        /// 0x01 ignore weapon, 0x02 bash, 0x04 power, 0x08 left, 0x10 rotating,
        /// 0x80000000 override.
        public let flags: UInt32
        public let attackAngle: Float
        public let strikeAngle: Float
        public let stagger: Float
        /// A KYWD.
        public let attackType: FormID?
        public let knockdown: Float
        public let recoveryTime: Float
        public let staminaMultiplier: Float

        init(_ reader: inout BinaryReader) throws {
            damageMultiplier = try reader.readFloat32()
            attackChance = try reader.readFloat32()
            spell = try reader.readFormID().nonNull
            flags = try reader.readUInt32()
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
}

/// MTYP plus its optional SPED speed overrides.
nonisolated public struct RaceMovementType: Equatable, Sendable {
    /// A MOVT.
    public var movementType: FormID?
    /// SPED: left, right, forward, back, rotate (walk then run), then one unnamed float.
    public var overrides: [Float] = []
}
