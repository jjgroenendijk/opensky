// Census probes for actor, race, and body records.

import Foundation
@testable import OpenSkyFormatsESM

extension FieldCensus {
    mutating func countActor(_ actor: ActorBase) {
        let details = actor.details
        count("NPC_", details, Self.actorDetails)
        count("NPC_ sound type", details.soundTypes, [("type", { $0.type })])
        count("NPC_ sound", details.soundTypes.flatMap(\.entries), [("sound", { $0.sound })])
        count("NPC_ tint layer", details.tintLayers, [
            ("index", { $0.index }), ("color", { $0.color }),
            ("interpolation", { $0.interpolation })
        ])
        countAttacks("NPC_ attack", details.attacks)
        countDestructible("NPC_", details.destructible)
        tally("NPC_", actor.skipped)
    }

    mutating func countRace(_ race: Race) {
        let details = race.details
        count("RACE", details, Self.raceDetails)
        count("RACE properties", details.properties, Self.raceProperties)
        count("RACE mount", details.properties?.mountOffsets, [
            ("mount", { $0.mount }), ("dismount", { $0.dismount }), ("camera", { $0.camera })
        ])
        count("RACE skill boost", details.properties?.skillBoosts ?? [], [
            ("skill", { $0.skill }), ("boost", { $0.boost })
        ])
        countAttacks("RACE attack", details.attacks)
        count("RACE movement", details.movementTypes, [("movementType", { $0.movementType })])
        countHead([details.headData.male, details.headData.female])
        tally("RACE", race.skipped)
    }

    private mutating func countHead(_ heads: [RaceHeadData]) {
        count("RACE head", heads, [
            ("defaultFaceTexture", { $0.defaultFaceTexture }), ("model", { $0.model })
        ])
        count("RACE head part", heads.flatMap(\.headParts), [("index", { $0.index })])
        count("RACE morph", heads.flatMap(\.morphs), [
            ("index", { $0.index }), ("flags", { $0.flags })
        ])
        let masks = heads.flatMap(\.tintMasks)
        count("RACE tint mask", masks, [
            ("index", { $0.index }), ("texturePath", { $0.texturePath }),
            ("maskType", { $0.maskType }), ("presetDefault", { $0.presetDefault })
        ])
        count("RACE tint preset", masks.flatMap(\.presets), [
            ("color", { $0.color }), ("index", { $0.index })
        ])
    }

    private mutating func countAttacks(_ owner: String, _ attacks: [RaceAttack]) {
        count(owner, attacks, [("properties", { $0.properties })])
        count("\(owner) data", attacks.compactMap(\.properties), Self.attackProperties)
    }

    mutating func countBodyParts(_ data: BodyPartData) {
        count("BPTD", data, [("formID", { $0.formID }), ("model", { $0.model })])
        count("BPTD part", data.parts, [
            ("poseMatching", { $0.poseMatching }), ("vatsTarget", { $0.vatsTarget }),
            ("ikStartNode", { $0.ikStartNode }),
            ("limbReplacementModel", { $0.limbReplacementModel }),
            ("goreTargetBone", { $0.goreTargetBone }),
            ("goreTextureHashes", { $0.goreTextureHashes })
        ])
        count("BPTD node", data.parts.compactMap(\.nodeData), Self.bodyPartNode)
        countModel(data.model)
        tally("BPTD", data.skipped)
    }

    mutating func countHeadPart(_ part: HeadPart) {
        count("HDPT", part, [
            ("name", { $0.name }), ("textureSet", { $0.textureSet }),
            ("validRaces", { $0.validRaces }), ("male", { $0.flags.contains(.male) }),
            ("female", { $0.flags.contains(.female) }),
            ("usesSolidTint", { $0.flags.contains(.usesSolidTint) })
        ])
        countModel(part.model)
        tally("HDPT", part.skipped)
    }

    mutating func countColor(_ color: ColorForm) {
        count("CLFM", color, [("formID", { $0.formID }), ("name", { $0.name })])
        tally("CLFM", color.skipped)
    }

    mutating func countEyes(_ eyes: Eyes) {
        count("EYES", eyes, [("formID", { $0.formID }), ("name", { $0.name })])
        tally("EYES", eyes.skipped)
    }

    mutating func countCombatStyle(_ style: CombatStyle) {
        count("CSTY", style, [
            ("formID", { $0.formID }), ("editorID", { $0.editorID }),
            ("strafeMultiplier", { $0.strafeMultiplier }), ("unknownCSMD", { $0.unknownCSMD }),
            ("allowsDualWieldingByHeader", { $0.allowsDualWieldingByHeader })
        ])
        count("CSTY close range", [style], CombatStyle.CloseRange.allCases.map { member in
            ("\(member)", { $0.value(member) })
        })
        tally("CSTY", style.skipped)
    }
}
