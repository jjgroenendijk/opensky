// The real-data half of item 15.6's acceptance (issue #197): the vanilla
// humanoid skeleton's ragdoll collapses onto a floor headlessly, with every
// constraint resolved and no unresolved bone names.
//
// Env-gated on `OPENSKY_DATA_ROOT` like every real-data suite, and headless: it
// decodes `skeleton.nif` and `skeleton.hkx` from the install, builds the ragdoll
// against the animation rig, drops it on a synthetic floor, and asserts on
// numbers. No renderer and no window, so it runs under `make realtest` on a
// machine with no display attached.
//
// The report goes to gitignored `logs/`. Nothing extracted from the install is
// written there: the file records bone names, joint counts and settle times,
// which are measurements rather than content.

import Foundation
@testable import opensky
import simd
import Testing

struct RagdollRealDataTests {
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

    /// The census reports 9 `bhkRagdollConstraint` and 8
    /// `bhkLimitedHingeConstraint` on this file over 18 `bhkRigidBody` blocks
    /// (`openskycli nif`, and docs/formats/nif-collision.md). A build that
    /// resolves fewer has lost a limb somewhere.
    private static let expectedBoneCount = 18
    private static let expectedJointCount = 17

    @Test(.enabled(if: Self.dataRoot != nil))
    func theVanillaHumanoidRagdollCollapsesOntoAFloor() throws {
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let definition = try #require(Self.definition(vfs: vfs), "no ragdoll built")

        // Every body resolved onto a bone and every joint onto two of them.
        Self.verifyDefinitionShape(definition)

        let bind = try Self.bindMatrices(vfs: vfs)
        var instance = try #require(RagdollInstance(
            definition: definition,
            animatedBoneMatrices: bind,
            actorToWorld: MatrixMath.translation(SIMD3(0, 0, 120)),
            blendDuration: 0.5,
            cell: .interior(FormID(1)),
            actor: FormID(1),
            key: .generated(1)
        ))

        // Drive the shared solver directly before `RagdollInstance` can apply
        // its whole-corpse displacement fallback. This is the regression for
        // issue #407: every vanilla bone must reach 15.2's ordinary sleep test.
        let ordinarySleepStep = Self.ordinarySleepStep(
            bodies: instance.bodies, joints: definition.joints
        )
        #expect(ordinarySleepStep != nil, "per-body sleep never settled every vanilla bone")

        // The joints start close to satisfied: a ragdoll handed off from the
        // bind pose is not already fighting its own limits.
        //
        // Close rather than exact, because vanilla authors slack into three of
        // the seventeen pivots — the knees by 4.3 engine units, the elbows by
        // 2.6, the neck by 1.4, symmetrically left and right, which is authored
        // data rather than a decode error. The bound is above the worst of
        // those and far below a bone length.
        Self.verifyInitialJointAlignment(definition: definition, instance: instance)

        let world = RagdollFixture.floorWorld()
        var settledStep: Int?
        var worstSeparation: Float = 0
        for step in 0 ..< 3600 {
            instance.step(world: world, dt: WalkController.fixedTimeStep)
            for joint in definition.joints {
                worstSeparation = max(
                    worstSeparation, RagdollFixture.separation(of: joint, in: instance)
                )
            }
            if settledStep == nil, instance.isSettled {
                settledStep = step
            }
        }
        // Settling is the whole-ragdoll displacement test, not 15.2's per-body
        // one: a jointed chain keeps a residual its bones never fall under
        // (issue #407). Within five seconds is the fall from a hundred and
        // twenty units, the bounce and the roll, plus the one-second window
        // that test watches for; the measured value is a little over four.
        #expect(settledStep ?? .max < 600, "settled at step \(settledStep ?? -1)")

        #expect(RagdollFixture.isFinite(instance), "the collapse produced a non-finite pose")
        #expect(instance.lastStats.recoveredBodyCount == 0)
        #expect(settledStep != nil, "the ragdoll never came to rest")
        // Every constraint resolved: at rest the pivots are back together to
        // within about a unit — a fortieth of a bone — and no limit is more
        // than two degrees outside its range. Measured at rest rather than at
        // the worst moment of the fall, which is what "resolved" means for a
        // solver that recovers over several substeps.
        //
        // Not tighter, because the solver stops when the ragdoll sleeps: the
        // corpse keeps the pose it settled into rather than being ground toward
        // zero forever by a pass nothing else is moving.
        #expect(worstSeparation < 12, "joints stretched to \(worstSeparation) units")
        for joint in definition.joints {
            let separation = RagdollFixture.separation(of: joint, in: instance)
            #expect(separation < 1.5, "a joint rests \(separation) units apart")
            let frames = joint.worldFrames(in: instance.bodies)
            for limit in RagdollJointLimitPass.passes(of: joint, frames: frames) {
                #expect(limit.error < 0.05, "a limit rests \(limit.error) radians outside")
            }
        }
        // Everything ends on or above the floor rather than through it.
        for body in instance.bodies {
            #expect(body.position.z > -20, "a bone fell through the floor")
        }

        try Self.write(
            report: Self.report(
                definition: definition,
                instance: instance,
                settledStep: settledStep,
                ordinarySleepStep: ordinarySleepStep,
                worstSeparation: worstSeparation
            )
        )
    }

    /// Every constraint class the skeleton carries is one this solver enforces
    /// limits for. A skeleton that introduced a prismatic joint would fail here
    /// rather than silently losing it.
    @Test(.enabled(if: Self.dataRoot != nil))
    func everyVanillaJointCarriesLimits() throws {
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let definition = try #require(Self.definition(vfs: vfs))
        var cones = 0
        var hinges = 0
        for joint in definition.joints {
            switch joint.limits {
            case .cone: cones += 1
            case .limitedHinge: hinges += 1
            case .hinge, .point, .distance:
                Issue.record("an unlimited joint reached the vanilla ragdoll")
            }
        }
        #expect(cones == 9, "expected 9 ragdoll cones, got \(cones)")
        #expect(hinges == 8, "expected 8 limited hinges, got \(hinges)")
    }

    // MARK: - Fixture

    private static func verifyDefinitionShape(_ definition: RagdollDefinition) {
        #expect(definition.skipped.isEmpty, "skipped: \(definition.skipped)")
        #expect(definition.boneCount == expectedBoneCount)
        #expect(definition.jointCount == expectedJointCount)
        #expect(Set(definition.bones.map(\.boneName)).count == definition.boneCount)
    }

    private static func verifyInitialJointAlignment(
        definition: RagdollDefinition,
        instance: RagdollInstance
    ) {
        for joint in definition.joints {
            let separation = RagdollFixture.separation(of: joint, in: instance)
            #expect(separation < 6, "joint starts \(separation) units apart")
        }
    }

    private static func ordinarySleepStep(
        bodies initialBodies: [DynamicBody],
        joints: [RagdollJointDefinition]
    ) -> Int? {
        var bodies = initialBodies
        for step in 0 ..< 3600 {
            DynamicBodySolver.step(
                bodies: &bodies,
                world: RagdollFixture.floorWorld(),
                dt: WalkController.fixedTimeStep,
                joints: joints
            )
            if bodies.allSatisfy(\.isSleeping) {
                return step
            }
        }
        return nil
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
    /// bodies are resolved against. `skeleton.hkx` carries two — the 99-bone
    /// animation rig and the 18-bone ragdoll physics skeleton — and it is the
    /// animation one this engine poses (docs/formats/hka-skeleton.md).
    private static func rig(vfs: VirtualFileSystem) throws -> HKASkeleton {
        let file = try HKXFile(data: vfs.contents(forPath: skeletonRig))
        let skeletons = try HKASkeleton.skeletons(in: file)
        let rig = skeletons.max { $0.boneNames.count < $1.boneNames.count }
        guard let rig else {
            throw RagdollRealDataError.noRig
        }
        return rig
    }

    private static func bindMatrices(vfs: VirtualFileSystem) throws -> [float4x4] {
        let skeleton = try rig(vfs: vfs)
        return try SkeletonPoseMath.worldMatrices(
            skeleton: skeleton, localPoses: skeleton.referencePose
        )
    }

    private static func report(
        definition: RagdollDefinition,
        instance: RagdollInstance,
        settledStep: Int?,
        ordinarySleepStep: Int?,
        worstSeparation: Float
    ) -> String {
        var lines = ["# Vanilla humanoid ragdoll (issue #197, item 15.6)", ""]
        lines.append("bones: \(definition.boneCount)")
        lines.append("joints: \(definition.jointCount)")
        lines.append("skipped: \(definition.skipped.count)")
        let settled = settledStep.map { "step \($0)" } ?? "never"
        lines.append("settled: \(settled)")
        let ordinarySleep = ordinarySleepStep.map { "step \($0)" } ?? "never"
        lines.append("ordinary per-body sleep: \(ordinarySleep)")
        lines.append(String(format: "worst joint separation: %.3f units", worstSeparation))
        lines.append("joint violations at rest: \(instance.lastStats.jointViolationCount)")
        lines.append("pose recoveries: \(instance.lastStats.recoveredBodyCount)")
        lines.append("")
        lines.append("## Bones and their resting height")
        for (index, bone) in definition.bones.enumerated() {
            let height = instance.bodies.indices.contains(index)
                ? instance.bodies[index].position.z : .nan
            lines.append(String(format: "  %@ — z %.2f", bone.boneName, height))
        }
        return lines.joined(separator: "\n") + "\n"
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
            to: directory.appending(path: "ragdoll-vanilla-humanoid.log"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private enum RagdollRealDataError: Error {
    case noRig
}
