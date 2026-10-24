// The ragdoll, shape, resource, and character helper classes decode on every
// archived `.hkx`, and their values make sense: pointers land on the class they
// name, transforms are rigid, and atom types are the same in every object. The
// report in `.logs/` holds class names, counts, and paths only.

import Foundation
@testable import OpenSkyFormatsAnimation
@testable import OpenSkyGameData
import simd
import Testing

struct HKXPhysicsDecodeRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func decodesEveryPhysicsAndHelperClass() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        var sweep = PhysicsSweep()
        for path in vfs.archiveEntries().map(\.path) where path.hasSuffix(".hkx") {
            guard
                let data = try? vfs.contents(forPath: path),
                let graph = try? HKXObjectGraph.decode(data)
            else { continue }
            sweep.record(graph, path: path)
        }
        try sweep.report().write(
            to: RepositoryLogs.directory().appending(path: "hkx-physics-decode.log"),
            atomically: true, encoding: .utf8
        )
        #expect(Set(sweep.objects.keys) == PhysicsSweep.checkedClasses)
        #expect(sweep.failed.isEmpty, "\(sweep.failed.prefix(5))")
        #expect(sweep.misreads.isEmpty, "\(sweep.misreads.prefix(5))")
        #expect(sweep.faults.isEmpty, "\(sweep.faults.prefix(10))")
        for (name, types) in sweep.atomTypes {
            #expect(types.allSatisfy { $0.count == 1 }, "\(name) atom types vary: \(types)")
        }
        #expect(sweep.gravityFactors == [1], "gravity factors \(sweep.gravityFactors)")
    }
}

private struct PhysicsSweep {
    static let checkedClasses: Set = [
        HKARagdollInstance.className, HKASkeletonMapper.className, HKPPhysicsData.className,
        HKPPhysicsSystem.className, HKPRigidBody.className, HKPConstraintInstance.className,
        HKPRagdollConstraintData.className, HKPLimitedHingeConstraintData.className,
        HKPPositionConstraintMotor.className, HKPShapeInfo.className,
        HKPCapsuleShape.className, HKPBoxShape.className, HKPConvexTranslateShape.className,
        HKPConvexTransformShapeObject.className, HKPConvexVerticesShape.className,
        HKPConvexVerticesConnectivity.className, HKPListShape.className,
        HKPMoppBvTreeShape.className, HKPMoppCode.className,
        HKMemoryResourceContainer.className, HKMemoryResourceHandle.className,
        HKADefaultAnimatedReferenceFrame.className,
        HKAInterleavedUncompressedAnimation.className, HKAAnnotationTrackObject.className,
        HKBMirroredSkeletonInfo.className, HKBFootIkDriverInfo.className,
        BGSGamebryoSequenceGenerator.className
    ]

    /// The atom type offsets of each constraint data class, in member order.
    static let atomOffsets = [
        HKPRagdollConstraintData.className: [
            0x20, 0xB0, 0xC0, 0x120, 0x12C, 0x140, 0x154, 0x168
        ],
        HKPLimitedHingeConstraintData.className: [0x20, 0xB0, 0xC0, 0xD8, 0xE4, 0xF4, 0xF8]
    ]

    static let shapeClasses: Set = [
        HKPCapsuleShape.className, HKPBoxShape.className, HKPConvexTranslateShape.className,
        HKPConvexTransformShapeObject.className, HKPConvexVerticesShape.className,
        HKPListShape.className, HKPMoppBvTreeShape.className, "hkpSphereShape",
        "hkpCylinderShape"
    ]

    var objects: [String: Int] = [:]
    var files: [String: Set<String>] = [:]
    var failed: [String] = []
    var misreads: [String] = []
    var faults: [String] = []
    var atomTypes: [String: [Set<Int>]] = [:]
    var gravityFactors: Set<Float> = []

    mutating func record(_ graph: HKXObjectGraph, path: String) {
        for ref in graph.objectRefs {
            guard let name = ref.className, Self.checkedClasses.contains(name) else { continue }
            objects[name, default: 0] += 1
            files[name, default: []].insert(path)
            let target = HKXPointerTarget(
                sectionIndex: ref.sectionIndex, dataOffset: ref.dataOffset
            )
            guard let object = HKBClassRegistry.decode(at: target, in: graph) else {
                failed.append("\(path): \(name)")
                continue
            }
            misreads += object.unresolved.filter { $0.miss != .noFixup }
                .map { "\(path): \(name).\($0.field) \($0.miss.rawValue)" }
            recordAtoms(name, at: target, in: graph)
            if let body = object as? HKPRigidBody {
                gravityFactors.insert(body.gravityFactor)
            }
            let checks = PhysicsChecks(graph: graph)
            faults += (checks.ragdoll(object) + checks.shapes(object) + checks.helpers(object))
                .map { "\(path): \(name) \($0)" }
        }
    }

    private mutating func recordAtoms(
        _ name: String, at target: HKXPointerTarget, in graph: HKXObjectGraph
    ) {
        guard let offsets = Self.atomOffsets[name], var cursor = graph.cursor(at: target) else {
            return
        }
        var types = atomTypes[name] ?? Array(repeating: [], count: offsets.count)
        for (index, offset) in offsets.enumerated() {
            let field = HKXField(offset, "atom[\(index)].m_type")
            types[index].insert(cursor.uint16(at: field) ?? -1)
        }
        atomTypes[name] = types
    }

    func report() -> String {
        var lines = ["OpenSky HKX physics and helper class sweep", ""]
        for name in objects.keys.sorted() {
            let paths = files[name] ?? []
            lines.append("\(name): \(objects[name] ?? 0) objects in \(paths.count) files, "
                + "first \(paths.min() ?? "-")")
        }
        lines += ["", "atom types:"]
        lines += atomTypes.keys.sorted().map { "\($0): \(atomTypes[$0] ?? [])" }
        lines += ["", "gravity factors: \(gravityFactors.sorted())"]
        lines += ["", "faults: \(faults.count)"] + faults.prefix(50)
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Value checks per class. Each returns the faults it found.
private struct PhysicsChecks {
    let graph: HKXObjectGraph

    func lands(_ pointer: HKXPointerTarget?, on names: Set<String>, _ member: String)
        -> [String]
    {
        guard let pointer else { return ["\(member) is null"] }
        let name = graph.className(at: pointer) ?? "<none>"
        return names.contains(name) ? [] : ["\(member) lands on \(name)"]
    }

    func ragdoll(_ object: any HKBClass) -> [String] {
        switch object {
        case let body as HKPRigidBody:
            return lands(body.shape, on: PhysicsSweep.shapeClasses, "shape")
                + (body.name == nil ? ["has no name"] : [])
                + (body.transform.isRigid ? [] : ["transform is not rigid"])
                + ((body.mass > 0 || body.isDrivenOrFixed) && body.mass.isFinite ? [] : [
                    "mass \(body.mass), motion \(body.motionType), \(body.name ?? "-")"
                ])
                + ((0 ... 10).contains(body.friction) ? [] : ["friction \(body.friction)"])
        case let instance as HKPConstraintInstance:
            let data = Set(PhysicsSweep.atomOffsets.keys)
            return lands(instance.entityA, on: [HKPRigidBody.className], "entity A")
                + lands(instance.entityB, on: [HKPRigidBody.className], "entity B")
                + lands(instance.data, on: data, "data")
        case let data as HKPRagdollConstraintData:
            let limits = [data.twistLimit, data.coneLimit, data.planesLimit]
            return frames(data.frames) + limits.filter {
                !($0.minAngle <= $0.maxAngle && abs($0.maxAngle) <= 4)
            }.map { "limit \($0)" }
        case let data as HKPLimitedHingeConstraintData:
            let limit = data.angleLimit
            return frames(data.frames) + (limit.minAngle <= limit.maxAngle ? [] : ["\(limit)"])
        case let ragdoll as HKARagdollInstance:
            return lands(ragdoll.skeleton, on: [HKASkeleton.className], "skeleton")
                + ragdoll.rigidBodies.flatMap { lands($0, on: [HKPRigidBody.className], "body") }
                + (ragdoll.boneToRigidBodyMap.allSatisfy { $0 < ragdoll.rigidBodies.count }
                    ? [] : ["bone map past the bodies"])
        case let mapper as HKASkeletonMapper:
            return lands(mapper.skeletonA, on: [HKASkeleton.className], "skeleton A")
                + lands(mapper.skeletonB, on: [HKASkeleton.className], "skeleton B")
                + (mapper.simpleMappings.allSatisfy(\.aFromBTransform.isValid)
                    ? [] : ["simple mapping transform"])
        default:
            return []
        }
    }

    func shapes(_ object: any HKBClass) -> [String] {
        let shapes = PhysicsSweep.shapeClasses
        switch object {
        case let capsule as HKPCapsuleShape:
            return capsule.header.radius > 0 ? [] : ["radius \(capsule.header.radius)"]
        case let box as HKPBoxShape:
            return simd_reduce_min(box.halfExtents) > 0 ? [] : ["extents \(box.halfExtents)"]
        case let hull as HKPConvexVerticesShape:
            let worst = hull.vertices.flatMap { vertex in
                hull.planeEquations.map { simd_dot($0.xyz, vertex) + $0.w }
            }.max() ?? 0
            // The export tool simplifies planes, so a vertex may sit a little outside.
            let size = simd_reduce_max(hull.aabbHalfExtents)
            return hull.vertices.isEmpty || worst > max(0.01, size * 0.05)
                ? ["hull vertices \(hull.vertices.count), worst \(worst), size \(size)"] : []
        case let shape as HKPConvexTranslateShape:
            return lands(shape.shape.childShape, on: shapes, "child")
        case let shape as HKPConvexTransformShapeObject:
            return lands(shape.shape.childShape, on: shapes, "child")
                + (shape.shape.transform.isRigid ? [] : ["transform is not rigid"])
        case let list as HKPListShape:
            return list.children.flatMap { lands($0.shape, on: shapes, "child") }
        case let tree as HKPMoppBvTreeShape:
            return lands(tree.code, on: [HKPMoppCode.className], "code")
                + lands(tree.childShape, on: shapes, "child")
        case let code as HKPMoppCode:
            return code.byteCount > 0 ? [] : ["no code"]
        default:
            return []
        }
    }

    func helpers(_ object: any HKBClass) -> [String] {
        switch object {
        case let sequence as BGSGamebryoSequenceGenerator:
            return sequence.sequence?.isEmpty ?? true ? ["no sequence name"] : []
        case let mirror as HKBMirroredSkeletonInfo:
            let bones = 0 ..< mirror.bonePairMap.count
            return mirror.bonePairMap.allSatisfy(bones.contains) ? [] : ["pair map"]
        case let footIk as HKBFootIkDriverInfo:
            let bad = footIk.legs.contains { $0.hipIndex < 0 || $0.ankleIndex < 0 }
            return bad ? ["leg bones"] : []
        case let animation as HKAInterleavedUncompressedAnimation:
            let expected = animation.frameCount * animation.transformTrackCount
            let good = animation.transforms.count == expected
                && animation.transforms.allSatisfy(\.isValid)
            return good ? [] : ["transforms"]
        case let frame as HKADefaultAnimatedReferenceFrame:
            return frame.samples.isEmpty || !frame.duration.isFinite ? ["samples"] : []
        default:
            return []
        }
    }

    private func frames(_ frames: HKPConstraintFrames) -> [String] {
        frames.transformA.isRigid && frames.transformB.isRigid ? [] : ["frames"]
    }
}
