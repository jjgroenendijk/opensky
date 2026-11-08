// The probe lists behind `FieldCensus+Actors.swift`.

import Foundation
@testable import OpenSkyFormatsESM

extension FieldCensus {
    static var actorDetails: [Probe<ActorBaseDetails>] {
        [
            ("bounds", { $0.bounds }), ("shortName", { $0.shortName }),
            ("keywords", { $0.keywords }), ("attacks", { $0.attacks }),
            ("deathItem", { $0.deathItem }), ("farAwayModel", { $0.farAwayModel }),
            ("attackRace", { $0.attackRace }), ("giftFilter", { $0.giftFilter }),
            ("spectatorOverride", { $0.spectatorOverride }),
            ("observeDeadOverride", { $0.observeDeadOverride }),
            ("guardWarnOverride", { $0.guardWarnOverride }),
            ("combatOverride", { $0.combatOverride }),
            ("defaultPackageList", { $0.defaultPackageList }),
            ("sleepingOutfit", { $0.sleepingOutfit }),
            ("inheritsSoundsFrom", { $0.inheritsSoundsFrom }), ("unknownNAM5", { $0.unknownNAM5 }),
            ("height", { $0.height }), ("weight", { $0.weight }), ("soundLevel", { $0.soundLevel }),
            ("headTexture", { $0.headTexture }), ("textureLighting", { $0.textureLighting })
        ]
    }

    static var raceDetails: [Probe<RaceDetails>] {
        [
            ("description", { $0.description }), ("tintCount", { $0.tintCount }),
            ("faceGenMainClamp", { $0.faceGenMainClamp }),
            ("faceGenFaceClamp", { $0.faceGenFaceClamp }), ("equipmentFlags", { $0.equipmentFlags })
        ]
    }

    static var raceProperties: [Probe<RaceProperties>] {
        [
            ("skillBoosts", { $0.skillBoosts }), ("unknown", { $0.unknown }),
            ("height", { $0.height.male }), ("weight", { $0.weight.male }), ("flags", { $0.flags }),
            ("startingHealth", { $0.startingHealth }), ("startingMagicka", { $0.startingMagicka }),
            ("startingStamina", { $0.startingStamina }), (
                "baseCarryWeight",
                { $0.baseCarryWeight }
            ),
            ("baseMass", { $0.baseMass }), ("accelerationRate", { $0.accelerationRate }),
            ("decelerationRate", { $0.decelerationRate }),
            ("headBipedObject", { $0.headBipedObject }), (
                "hairBipedObject",
                { $0.hairBipedObject }
            ),
            ("injuredHealthPercent", { $0.injuredHealthPercent }),
            ("shieldBipedObject", { $0.shieldBipedObject }), ("healthRegen", { $0.healthRegen }),
            ("magickaRegen", { $0.magickaRegen }), ("staminaRegen", { $0.staminaRegen }),
            ("unarmedDamage", { $0.unarmedDamage }), ("unarmedReach", { $0.unarmedReach }),
            ("bodyBipedObject", { $0.bodyBipedObject }),
            ("aimAngleTolerance", { $0.aimAngleTolerance }), ("flightRadius", { $0.flightRadius }),
            ("angularAccelerationRate", { $0.angularAccelerationRate }),
            ("angularTolerance", { $0.angularTolerance }), ("flags2", { $0.flags2 })
        ]
    }

    static var attackProperties: [Probe<RaceAttack.Properties>] {
        [
            ("damageMultiplier", { $0.damageMultiplier }), ("attackChance", { $0.attackChance }),
            ("spell", { $0.spell }), ("flags", { $0.flags }), ("attackAngle", { $0.attackAngle }),
            ("strikeAngle", { $0.strikeAngle }), ("stagger", { $0.stagger }),
            ("attackType", { $0.attackType }), ("knockdown", { $0.knockdown }),
            ("recoveryTime", { $0.recoveryTime }), ("staminaMultiplier", { $0.staminaMultiplier })
        ]
    }

    static var bodyPartNode: [Probe<BodyPartNodeData>] {
        [
            ("damageMultiplier", { $0.damageMultiplier }), ("flags", { $0.flags }),
            ("healthPercent", { $0.healthPercent }), ("toHitChance", { $0.toHitChance }),
            ("explosionChance", { $0.explosionChance }), (
                "explodableDebris",
                { $0.explodableDebris }
            ),
            ("explodableExplosion", { $0.explodableExplosion }),
            ("trackingMaxAngle", { $0.trackingMaxAngle }),
            ("explodableDebrisScale", { $0.explodableDebrisScale }),
            ("severableDebrisCount", { $0.severableDebrisCount }),
            ("severableDebris", { $0.severableDebris }),
            ("severableExplosion", { $0.severableExplosion }),
            ("severableDebrisScale", { $0.severableDebrisScale }), (
                "goreOffset",
                { $0.goreOffset }
            ),
            ("goreRotation", { $0.goreRotation }),
            ("severableImpactDataSet", { $0.severableImpactDataSet }),
            ("explodableImpactDataSet", { $0.explodableImpactDataSet }),
            ("severableDecalCount", { $0.severableDecalCount }),
            ("explodableDecalCount", { $0.explodableDecalCount }), ("unknown", { $0.unknown }),
            ("limbReplacementScale", { $0.limbReplacementScale })
        ]
    }
}
