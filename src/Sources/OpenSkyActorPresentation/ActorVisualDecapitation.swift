// A decapitated actor draws as two pieces of one look. The body keeps what is below the
// cut and wears the race's neck stump. The head keeps the face, hair, and helmet, and
// wears the head's gore cap. Both come from the race's `DNAM` armour
// (docs/engine/ragdoll.md#decapitation).

import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyWorldInterface

/// The two pieces a cut makes of one actor.
nonisolated public struct DecapitatedVisual: Equatable, Sendable {
    public let body: ResolvedActorVisual
    public let head: ResolvedActorVisual
}

nonisolated extension ResolvedActorVisual {
    /// Worn slots wholly above the cut. A piece that covers only these goes with the head.
    public static let headSideSlots: BodySlots = [
        .head, .hair, .longHair, .circlet, .ears, .decapitatedHead
    ]

    /// This look split at the neck. `gore` is the race's decapitation armour: its slot 51
    /// armature joins the body, its slot 50 armature the head. The face and head parts
    /// are drawn on both, each keeping its own side of their partitions.
    public func decapitated(gore: [ResolvedBodyPart]) -> DecapitatedVisual {
        var bodyPieces: [ResolvedBodyPart] = []
        var headPieces: [ResolvedBodyPart] = []
        for part in parts + gore {
            if !part.slots.isEmpty, part.slots.isSubset(of: Self.headSideSlots) {
                headPieces.append(part)
                continue
            }
            if part.slots.contains(.decapitate) {
                bodyPieces.append(part)
                continue
            }
            var lower = part
            lower.cut = DismemberCut(side: .body, keepsUnpartitioned: true)
            bodyPieces.append(lower)
            if part.slots.overlaps(Self.headSideSlots) {
                var upper = part
                upper.cut = DismemberCut(side: .head, keepsUnpartitioned: false)
                headPieces.append(upper)
            }
        }
        var body = replacing(parts: bodyPieces, attachments: attachments)
        body.headCut = DismemberCut(side: .body, keepsUnpartitioned: false)
        var head = replacing(parts: headPieces, attachments: [])
        head.headCut = DismemberCut(side: .head, keepsUnpartitioned: true)
        return DecapitatedVisual(body: body, head: head)
    }

    private func replacing(
        parts: [ResolvedBodyPart], attachments: [ResolvedAttachment]
    ) -> ResolvedActorVisual {
        var copy = ResolvedActorVisual(
            appearance: appearance,
            skeletonPath: skeletonPath,
            skin: skin,
            equippedSlots: equippedSlots,
            parts: parts,
            attachments: attachments,
            usesRuntimeEquipment: usesRuntimeEquipment,
            faceGenMeshPath: faceGenMeshPath,
            faceGenTintPath: faceGenTintPath,
            skips: skips
        )
        copy.headParts = headParts
        copy.headSource = headSource
        copy.faceGenSurface = faceGenSurface
        return copy
    }
}

nonisolated extension ActorVisualResolver {
    /// The race's decapitation armour (`RACE DNAM`) as parts for this look, each with its
    /// own skin texture. Empty when the race names none.
    public func decapitationGore(for visual: ResolvedActorVisual) -> [ResolvedBodyPart] {
        guard
            let raceID = visual.appearance.race.value,
            let pair = races[raceID.rawValue]?.details.decapitateArmors
        else { return [] }
        let female = visual.appearance.isFemale.value
        guard
            let armorID = female ? pair.female ?? pair.male : pair.male ?? pair.female,
            let armor = armors[armorID.rawValue]
        else { return [] }
        var seen: Set<UInt32> = []
        var skips: [AppearanceSkip] = []
        let selection = PartSelection(
            origin: .outfit(armor.formID), race: raceID, female: female, mask: nil
        )
        return bodyParts(of: armor, selection: selection, seen: &seen, skips: &skips).map {
            var part = $0.part
            part.skinTextures = ownSkinTextures(of: part.armature, female: female)
            return part
        }
    }
}
