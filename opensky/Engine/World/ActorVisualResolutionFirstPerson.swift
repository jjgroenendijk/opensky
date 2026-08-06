// Projecting a resolved actor visual onto the first-person rig (issue #190).
//
// Vanilla ships a complete parallel set for first person — its own skeleton
// (`_1stperson\skeleton.nif`), its own Havok rig, its own behavior files, and
// per-armature first-person meshes in ARMA MOD4/MOD5. What it does *not* ship
// is a second resolution chain: the same NPC_, the same RACE, the same worn
// ARMOs, and the same slot mask decide what is on the player in both views.
// So this is a projection of the third-person answer rather than a second
// resolve, which is what keeps "equipping in the menu changes both rigs" true
// by construction instead of by two code paths agreeing.
//
// Three things change and nothing else:
//
// * The skeleton becomes the first-person one. RACE names only the
//   third-person rig (ANAM), so the first-person path is a constant
//   (`PlayerBehaviorGraph.firstPersonRigPath`); the install ships exactly one
//   and no record points at it.
// * Each part's model becomes its MOD4/MOD5. A part whose armature declares
//   neither is dropped with reason `noFirstPersonModel`.
// * The FaceGen head goes away. The eye is inside it.
//
// Attachments — the drawn weapon of the M12 equipment path — carry across
// unchanged, because the bone they ride is spelled identically in both rigs:
// `openskycli skeleton` over `_1stperson\characterassets\skeletonfirst.hkx`
// reports the same 99 bone names the third-person rig uses for the arms and
// hands, `Weapon` included.
//
// **Why a missing MOD4 drops the piece rather than falling back to MOD2.**
// This is the flagged assumption of the projection, and it is chosen from
// counts rather than from a hunch. Sweeping all 766 ARMA records in
// `Skyrim.esm` and grouping by biped slot: the torso group declares a
// first-person model in 90 of 94 armatures and the hand/forearm group in 28 of
// 42, while the head group declares one in 0 of 58, hair in 0 of 42, and feet
// in 0 of 34. The data therefore uses the *absence* of MOD4 to say "this piece
// is not visible from the eye" — falling back to MOD2 would hang a helmet in
// front of the camera. The cost is that an armature which is visible from the
// eye but declares no MOD4 (vanilla iron gauntlets, `ArmorIronGauntletsAA`,
// are one of the 14) shows nothing rather than showing its third-person mesh.
// That is a visible gap in the right direction — an arm with no glove reads as
// missing data, where an invented fallback reads as a bug somewhere else — and
// every one of them is a reason-tagged skip the panel reports.

import Foundation

nonisolated extension ResolvedActorVisual {
    /// This visual as the first-person rig wears it.
    ///
    /// - Parameter skeletonPath: the first-person NIF skeleton the arm meshes
    ///   skin against, passed in rather than hardcoded here so a test can
    ///   project onto a synthetic rig.
    func firstPersonProjection(skeletonPath: String) -> ResolvedActorVisual {
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
