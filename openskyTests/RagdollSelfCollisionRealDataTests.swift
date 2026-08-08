// The real-data half of issue #413's acceptance: what the vanilla humanoid
// skeleton's Havok biped filter bits actually say, and what they admit.
//
// Split from `RagdollRealDataTests` for the type-length limit, and gated and
// shaped exactly like it: `OPENSKY_DATA_ROOT` only, headless, no renderer, and
// a report into gitignored `logs/`. Nothing extracted from the install is
// written there — the file records bone names and pair counts, which are
// measurements rather than content.
//
// The synthetic half lives in `RagdollSelfCollisionTests`, which needs no
// install.

import Foundation
@testable import opensky
import simd
import Testing

struct RagdollSelfCollisionRealDataTests {
    /// Real data only when explicitly pointed at via the env var; the locator's
    /// Steam-default fallback is deliberately not consulted so machines without
    /// the override skip deterministically.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static let skeletonMesh = "meshes\\actors\\character\\character assets\\skeleton.nif"
    private static let skeletonRig = "meshes\\actors\\character\\character assets\\skeleton.hkx"

    /// The vanilla humanoid's biped filter bits, and what they admit (issue
    /// #413).
    ///
    /// The part numbers are asserted by name against nif.xml's `BipedPart` enum,
    /// bone by bone, because that anatomy lining up is the evidence the mask is
    /// read at the right width and offset. A part number read from the wrong
    /// bits would still be *a* number; it would not put `P_L_CALF` on the left
    /// calf.
    @Test(.enabled(if: Self.dataRoot != nil))
    func theVanillaHumanoidCarriesBipedPartsOnEveryBone() throws {
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let model = try NIFCollisionLibrary(fileSystem: vfs).model(path: Self.skeletonMesh)
        for body in model.bodies where body.dynamics.isSimulated {
            let name = body.targetName ?? ""
            // Every body is on SKYL_BIPED with no No Collision bit, in group 0.
            #expect(body.worldFilter.layer == 8, "\(name) is not on the biped layer")
            #expect(body.rigidBodyFilter.layer == 8)
            #expect(!body.hasNoCollision, "\(name) carries No Collision")
            #expect(body.worldFilter.group == 0)
            // The two duplicate filters agree, which is why either may be read.
            #expect(body.worldFilter == body.rigidBodyFilter, "\(name)'s filters disagree")
            #expect(
                body.bipedPart == Self.expectedBipedParts[name],
                Comment(rawValue: "\(name) reads part "
                    + (body.bipedPart.map(String.init) ?? "none"))
            )
        }
    }

    /// What the admitted set comes to on the real skeleton: a large majority of
    /// the pairs, and **none of the ones that already overlap at the bind pose**.
    ///
    /// That second half is the whole acceptance for issue #413. Item 15.6 turned
    /// self-collision off because a corpse lying still carried 30 to 45 standing
    /// contacts; if the filter admits no pair that is interpenetrating before
    /// anything has moved, those contacts cannot exist.
    @Test(.enabled(if: Self.dataRoot != nil))
    func theBipedFilterAdmitsNoPairThatOverlapsAtTheBindPose() throws {
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let definition = try #require(Self.definition(vfs: vfs))
        let bind = try Self.bindMatrices(vfs: vfs)
        let instance = try #require(RagdollInstance(
            definition: definition,
            animatedBoneMatrices: bind,
            actorToWorld: MatrixMath.translation(SIMD3(0, 0, 120)),
            blendDuration: 0,
            cell: .interior(FormID(1)),
            actor: FormID(1),
            key: .generated(1)
        ))
        let overlapping = Self.overlappingPairs(of: instance)
        // Measured: 24 of the 153 pairs are interpenetrating at the bind pose,
        // and 63 pairs are admitted. Bounds rather than equalities on the two
        // counts, because they are properties of Bethesda's authored capsule
        // radii; the disjointness below is the statement that has to hold
        // exactly.
        #expect(!overlapping.isEmpty, "no pair overlaps at all — the fixture is not loaded")
        #expect(definition.selfCollision.pairCount > definition.boneCount)
        for pair in overlapping {
            #expect(
                !definition.selfCollision.admits(pair.first, pair.second),
                Comment(rawValue: "\(definition.bones[pair.first].boneName) and "
                    + "\(definition.bones[pair.second].boneName) overlap at the bind pose "
                    + "and are admitted anyway")
            )
        }
        try Self.write(report: Self.selfCollisionReport(
            definition: definition, overlapping: overlapping
        ))
    }

    // MARK: - Fixture

    /// nif.xml `BipedPart` by the bone the vanilla humanoid puts it on. Spelled
    /// out rather than derived, so a decode that shifted every part by one would
    /// fail here instead of quietly agreeing with itself.
    private static let expectedBipedParts: [String: UInt8] = [
        "NPC Neck [Neck]": 0, // P_OTHER
        "NPC Head [Head]": 1, // P_HEAD
        "NPC COM [COM ]": 2, // P_BODY
        "NPC Spine [Spn0]": 2, // P_BODY
        "NPC Spine1 [Spn1]": 3, // P_SPINE1
        "NPC Spine2 [Spn2]": 4, // P_SPINE2
        "NPC L UpperArm [LUar]": 5, // P_L_UPPER_ARM
        "NPC L Forearm [LLar]": 6, // P_L_FOREARM
        "NPC L Hand [LHnd]": 7, // P_L_HAND
        "NPC L Thigh [LThg]": 8, // P_L_THIGH
        "NPC L Calf [LClf]": 9, // P_L_CALF
        "NPC L Foot [Lft ]": 10, // P_L_FOOT
        "NPC R UpperArm [RUar]": 11, // P_R_UPPER_ARM
        "NPC R Forearm [RLar]": 12, // P_R_FOREARM
        "NPC R Hand [RHnd]": 13, // P_R_HAND
        "NPC R Thigh [RThg]": 14, // P_R_THIGH
        "NPC R Calf [RClf]": 15, // P_R_CALF
        "NPC R Foot [Rft ]": 16 // P_R_FOOT
    ]

    /// Every bone pair whose capsules interpenetrate at the pose the ragdoll was
    /// handed off in, through the same narrowphase the solver uses.
    private static func overlappingPairs(of instance: RagdollInstance) -> [RagdollBonePair] {
        let bodies = instance.bodies
        let samples = bodies.map { $0.contactSamples() }
        var pairs: [RagdollBonePair] = []
        for first in bodies.indices {
            for second in bodies.indices where second > first {
                let contacts = DynamicBodyContacts.pairContacts(
                    first: DynamicBodySamples(
                        body: bodies[first], index: first, samples: samples[first]
                    ),
                    second: DynamicBodySamples(
                        body: bodies[second], index: second, samples: samples[second]
                    )
                )
                guard !contacts.isEmpty else { continue }
                pairs.append(RagdollBonePair(first, second))
            }
        }
        return pairs
    }

    private static func selfCollisionReport(
        definition: RagdollDefinition,
        overlapping: [RagdollBonePair]
    ) -> String {
        let total = definition.boneCount * (definition.boneCount - 1) / 2
        var lines = ["# Vanilla humanoid ragdoll self-collision (issue #413)", ""]
        lines.append("bones: \(definition.boneCount)")
        lines.append("possible pairs: \(total)")
        lines.append("admitted pairs: \(definition.selfCollision.pairCount)")
        lines.append("overlapping at the bind pose: \(overlapping.count)")
        lines.append("")
        lines.append("## Biped parts")
        for bone in definition.bones {
            lines.append("  \(bone.boneName) — part \(bone.bipedPart.map(String.init) ?? "none")")
        }
        lines.append("")
        lines.append("## Overlapping at the bind pose, all rejected")
        for pair in overlapping {
            lines.append("  \(definition.bones[pair.first].boneName)"
                + " x \(definition.bones[pair.second].boneName)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func definition(vfs: VirtualFileSystem) -> RagdollDefinition? {
        guard
            let model = try? NIFCollisionLibrary(fileSystem: vfs).model(path: skeletonMesh),
            let bind = try? bindMatrices(vfs: vfs),
            let skeleton = try? rig(vfs: vfs)
        else { return nil }
        return RagdollDefinition(
            model: model, boneNames: skeleton.boneNames, bindMatrices: bind
        )
    }

    /// The animation rig, which is the skeleton whose bone names the ragdoll
    /// bodies are resolved against (docs/formats/hka-skeleton.md).
    private static func rig(vfs: VirtualFileSystem) throws -> HKASkeleton {
        let file = try HKXFile(data: vfs.contents(forPath: skeletonRig))
        let skeletons = try HKASkeleton.skeletons(in: file)
        guard let rig = skeletons.max(by: { $0.boneNames.count < $1.boneNames.count }) else {
            throw RagdollSelfCollisionRealDataError.noRig
        }
        return rig
    }

    private static func bindMatrices(vfs: VirtualFileSystem) throws -> [float4x4] {
        let skeleton = try rig(vfs: vfs)
        return try SkeletonPoseMath.worldMatrices(
            skeleton: skeleton, localPoses: skeleton.referencePose
        )
    }

    private static func write(report: String) throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        try report.write(
            to: directory.appending(path: "ragdoll-self-collision.log"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private enum RagdollSelfCollisionRealDataError: Error {
    case noRig
}
