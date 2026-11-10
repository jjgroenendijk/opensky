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
    nonisolated struct SkillBoost: Equatable, Sendable {
        /// An actor-value index, -1 for none.
        let skill: Int8
        let boost: Int8
    }

    /// Mount data: where a rider sits, steps off, and the camera goes.
    nonisolated public struct MountOffsets: Equatable, Sendable {
        let mount: SIMD3<Float>
        public let dismount: SIMD3<Float>
        let camera: SIMD3<Float>

        /// Where a rider steps off a race without mount data: left of the saddle, above it.
        public static let fallbackDismount = SIMD3<Float>(-50, 0, 65)
    }

    let skillBoosts: [SkillBoost]
    /// Two bytes xEdit leaves unnamed.
    let unknown: UInt16
    let height: GenderPair<Float>
    let weight: GenderPair<Float>
    /// The flags `Race.Flags` names in part.
    let flags: UInt32
    let startingHealth: Float
    let startingMagicka: Float
    let startingStamina: Float
    let baseCarryWeight: Float
    let baseMass: Float
    let accelerationRate: Float
    let decelerationRate: Float
    /// 0 small, 1 medium, 2 large, 3 extra large.
    public let size: UInt32
    /// Biped slot indices, -1 for none.
    let headBipedObject: Int32
    let hairBipedObject: Int32
    public let injuredHealthPercent: Float
    let shieldBipedObject: Int32
    let healthRegen: Float
    let magickaRegen: Float
    let staminaRegen: Float
    let unarmedDamage: Float
    let unarmedReach: Float
    let bodyBipedObject: Int32
    let aimAngleTolerance: Float
    let flightRadius: Float
    let angularAccelerationRate: Float
    let angularTolerance: Float
    /// 0x01 advanced avoidance, 0x02 non-hostile, 0x10 allow mounted combat.
    /// Optional in xEdit.
    let flags2: UInt32?
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
nonisolated struct RaceAttack: Equatable, Sendable {
    nonisolated struct Properties: Equatable, Sendable {
        let damageMultiplier: Float
        let attackChance: Float
        /// A SPEL or SHOU.
        let spell: FormID?
        /// 0x01 ignore weapon, 0x02 bash, 0x04 power, 0x08 left, 0x10 rotating,
        /// 0x80000000 override.
        let flags: UInt32
        let attackAngle: Float
        let strikeAngle: Float
        let stagger: Float
        /// A KYWD.
        let attackType: FormID?
        let knockdown: Float
        let recoveryTime: Float
        let staminaMultiplier: Float

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

    var properties: Properties?
    /// ATKE, the animation event that starts the attack.
    var event: String?
}

/// MTYP plus its optional SPED speed overrides.
nonisolated struct RaceMovementType: Equatable, Sendable {
    /// A MOVT.
    var movementType: FormID?
    /// SPED: left, right, forward, back, rotate (walk then run), then one unnamed float.
    var overrides: [Float] = []
}
