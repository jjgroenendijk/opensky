// Projects a resolved actor visual onto the first-person rig, so one resolve serves both
// views. The skeleton becomes `PlayerBehaviorGraph.firstPersonRigPath`, each part uses
// MOD4/MOD5, and the FaceGen head goes. A part without MOD4 is dropped, not given MOD2:
// in Skyrim.esm no head, hair or feet armature has one, so absence means "not visible
// from the eye". Iron gauntlets lose their glove as a result; the panel reports it.

import Foundation

nonisolated extension ResolvedActorVisual {
    /// This visual as the first-person rig wears it.
    ///
    /// - Parameter skeletonPath: the first-person NIF skeleton the arm meshes
    ///   skin against, passed in rather than hardcoded here so a test can
    ///   project onto a synthetic rig.
    public func firstPersonProjection(skeletonPath: String) -> ResolvedActorVisual {
        var skips = skips
        var parts: [ResolvedBodyPart] = []
        for part in self.parts {
            guard let path = part.firstPersonModelPath else {
                skips.append(AppearanceSkip(
                    subject: part.armature, reason: .noFirstPersonModel
                ))
                continue
            }
            parts.append(ResolvedBodyPart(
                origin: part.origin,
                armature: part.armature,
                modelPath: path,
                firstPersonModelPath: path,
                slots: part.slots
            ))
        }
        return ResolvedActorVisual(
            appearance: appearance,
            skeletonPath: skeletonPath,
            skin: skin,
            equippedSlots: equippedSlots,
            parts: parts,
            attachments: attachments,
            usesRuntimeEquipment: usesRuntimeEquipment,
            // No head: the eye is inside it, and the vanilla first-person rig
            // carries no FaceGen geometry at all.
            faceGenMeshPath: nil,
            faceGenTintPath: nil,
            skips: skips
        )
    }
}
