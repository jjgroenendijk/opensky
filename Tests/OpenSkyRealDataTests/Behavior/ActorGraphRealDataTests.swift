// Actor graphs on the real install: the Nord and wolf races name their graph projects, each
// graph steps, a walking NPC's graph fires its own footstep events, and a standing NPC's pose
// follows its weight. Asserts on event names, counts, and joint positions only.

import Foundation
@testable import OpenSkyActorPresentation
@testable import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import simd
import Testing

struct ActorGraphRealDataTests {
    private static let timestep: Float = 1.0 / 30.0
    /// Three seconds is several walk cycles.
    private static let stepCount = 90
    private static let walkSpeed: Float = 80

    private struct Run {
        var firedEvents: Set<String> = []
        var posedSteps = 0
        var activeStateCount = 0
        var declaredEvents: Set<String> = []
        var skeleton: BehaviorSkeleton?
        var lastBones: [HKABonePose]?
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func anNPCAndACreatureStepTheirRaceGraphs() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let loadOrder = try ActiveLoadOrder.open(root: root).plugins
        var skipped = SkippedRecords()
        let races = loadOrder.decodeRecords(of: "RACE", skipped: &skipped) {
            try Race(record: $0, localized: $1)
        }
        let vfs = VirtualFileSystem(root: root)

        let nord = try run(race: "NordRace", races: races, files: vfs)
        #expect(nord.posedSteps > 0)
        #expect(nord.activeStateCount > 0)
        #expect(nord.firedEvents.contains("FootLeft"), "fired: \(nord.firedEvents.sorted())")
        #expect(nord.firedEvents.contains("FootRight"), "fired: \(nord.firedEvents.sorted())")
        let lowered = Set(nord.declaredEvents.map { $0.lowercased() })
        for name in ["IdleForceDefaultState", "WeapEquip", "Unequip", "moveStart"] {
            #expect(lowered.contains(name.lowercased()), "the human graph lacks \(name)")
        }

        let wolf = try run(race: "WolfRace", races: races, files: vfs)
        #expect(wolf.posedSteps > 0)
        #expect(wolf.activeStateCount > 0)
        print("[INFO] wolf fired: \(wolf.firedEvents.sorted())")
        print("[INFO] nord fired: \(nord.firedEvents.sorted())")
    }

    /// A standing NPC plays its idle with the body-weight layer added on top, an
    /// additive clip. Played as a full pose, that layer lifts the arms into a T-pose.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func aStandingNPCGraphPosesItsArmsDown() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let loadOrder = try ActiveLoadOrder.open(root: root).plugins
        var skipped = SkippedRecords()
        let races = loadOrder.decodeRecords(of: "RACE", skipped: &skipped) {
            try Race(record: $0, localized: $1)
        }
        let vfs = VirtualFileSystem(root: root)
        let skinny = InstallBehaviorClipSource(fileSystem: vfs)
            .clip(named: "mt_idle_skinny.hkx", bindingIndex: 0)
        #expect(skinny?.isAdditive == true, "the body-weight layer is not additive")

        let nord = try run(race: "NordRace", races: races, files: vfs, motion: .still)
        let skeleton = try #require(nord.skeleton)
        let arm = try #require(
            skeleton.boneNames.firstIndex { $0.hasPrefix("NPC L UpperArm") }, "no upper arm"
        )
        let forearm = try #require(
            skeleton.boneNames.firstIndex { $0.hasPrefix("NPC L Forearm") }, "no forearm"
        )
        let bones = try #require(nord.lastBones)
        let drop = Self.armDrop(bones, skeleton: skeleton, from: arm, to: forearm)
        print("[INFO] upper arm below horizontal: \(drop) degrees")
        #expect(drop > 45, "the arm stays near the T-pose")
    }

    /// The body-weight layers draw a thin NPC's arms in (`MT_Idle_Skinny`) and push a heavy
    /// NPC's arms out (`MT_IdleMuscularOffset`), so the hands sit closer on a thin NPC.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func aThinNPCHoldsItsHandsCloserThanAHeavyOne() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let loadOrder = try ActiveLoadOrder.open(root: root).plugins
        var skipped = SkippedRecords()
        let races = loadOrder.decodeRecords(of: "RACE", skipped: &skipped) {
            try Race(record: $0, localized: $1)
        }
        let vfs = VirtualFileSystem(root: root)
        func handGap(weight: Float) throws -> Float {
            let nord = try run(
                race: "NordRace",
                races: races,
                files: vfs,
                motion: .still,
                weight: weight
            )
            let skeleton = try #require(nord.skeleton)
            let model = try Self.modelPositions(#require(nord.lastBones), skeleton: skeleton)
            let hands = ["NPC L Hand", "NPC R Hand"].compactMap { name in
                skeleton.boneNames.firstIndex { $0.hasPrefix(name) }
            }
            try #require(hands.count == 2, "no hands")
            return simd_distance(model[hands[0]], model[hands[1]])
        }
        let thin = try handGap(weight: 0), heavy = try handGap(weight: 100)
        print("[INFO] hand gap: weight 0 \(thin), weight 100 \(heavy)")
        #expect(thin + 5 < heavy, "the body-weight layers do not reach the pose")
    }

    /// Degrees the shoulder-to-elbow line points below the model's horizontal plane.
    private static func armDrop(
        _ pose: [HKABonePose], skeleton: BehaviorSkeleton, from arm: Int, to forearm: Int
    ) -> Float {
        let model = modelPositions(pose, skeleton: skeleton)
        let line = model[forearm] - model[arm]
        return asin(-line.z / simd_length(line)) * 180 / .pi
    }

    private static func modelPositions(_ pose: [HKABonePose], skeleton: BehaviorSkeleton)
        -> [SIMD3<Float>]
    {
        var model = [simd_float4x4](repeating: matrix_identity_float4x4, count: pose.count)
        for (index, bone) in pose.enumerated() {
            var local = simd_float4x4(bone.rotation)
            local.columns.3 = SIMD4(bone.translation, 1)
            let parent = skeleton.parent(of: index)
            model[index] = parent >= 0 ? model[parent] * local : local
        }
        return model.map { SIMD3($0.columns.3.x, $0.columns.3.y, $0.columns.3.z) }
    }

    private func run(
        race editorID: String, races: [Race], files: VirtualFileSystem,
        motion: ActorGraphMotion = ActorGraphMotion(isMoving: true), weight: Float = 50
    ) throws -> Run {
        let race = try #require(races.last { $0.editorID == editorID }, "no \(editorID)")
        let model = try #require(race.details.behaviorGraphs.male, "\(editorID) names no graph")
        let path = ActorGraphCore.projectPath(modelPath: model.path)
        let asset = try BehaviorProjectAsset.load(
            fileSystem: files, projectPath: path, folderClips: true
        )
        let instance = BehaviorGraphInstance(
            graph: asset.behavior, in: asset.objectGraph,
            skeleton: BehaviorSkeleton(asset.skeleton),
            clips: InstallBehaviorClipSource(fileSystem: files, paths: asset.clipPaths)
        )
        instance.references = InstallBehaviorReferenceSource(
            fileSystem: files,
            pathsByName: InstallBehaviorReferenceSource.index(files, rootPath: asset.behaviorPath)
        )
        instance.activate()
        let walking = motion
        var result = Run(declaredEvents: Set(asset.eventNames), skeleton: instance.skeleton)
        for step in 0 ..< Self.stepCount {
            var input = ActorGraphStepInput(
                motion: walking, speed: walking.isMoving ? Self.walkSpeed : 0, turnDelta: 0,
                deltaTime: Self.timestep
            )
            input.weight = weight
            for (name, value) in ActorGraphCore.variables(input) {
                instance.setVariable(value, named: name)
            }
            if step == 0 {
                for event in ActorGraphCore.events(from: .still, to: walking) {
                    instance.raiseEvent(named: event)
                }
            }
            let update = instance.update(deltaTime: Self.timestep)
            result.posedSteps += update.bones.isEmpty ? 0 : 1
            result.lastBones = update.bones.isEmpty ? result.lastBones : update.bones
            result.firedEvents.formUnion(update.firedEvents.compactMap(\.name))
            result.activeStateCount = max(result.activeStateCount, instance.activeStates.count)
        }
        return result
    }
}
