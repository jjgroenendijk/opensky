// Reads the nodes and the free-running node controllers of a mesh into a
// `NIFNodeAnimation`. Layout: docs/formats/nif-controllers.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated struct NIFNodeAnimationDecoder {
    let file: NIFFile
    private(set) var nodes: [NIFNodeAnimation.Node] = []
    private(set) var controllers: [NIFNodeAnimation.Controller] = []
    private var nodeOfBlock: [Int: Int] = [:]
    private var controllerRefs: [Int32] = []
    private var lodController: NIFBoneLODController?
    private var lodDistances: [NIFBoneLOD] = []

    init(file: NIFFile) {
        self.file = file
    }

    mutating func readNodes() throws {
        var objects: [(block: Int, object: NIFObjectPrefix)] = []
        for (index, block) in file.blocks.enumerated()
            where NIFNodeAnimation.nodeTypes.contains(block.typeName)
        {
            var reader = BinaryReader(block.data)
            let object = try NIFObjectPrefix(reader: &reader, header: file.header)
            nodeOfBlock[index] = objects.count
            objects.append((index, object))
        }
        let parents = file.nodeParents()
        nodes = objects.map { entry in
            NIFNodeAnimation.Node(
                block: entry.block,
                name: entry.object.name,
                parent: parents[entry.block].flatMap { nodeOfBlock[$0] },
                rest: NIFNodeTransform(
                    translation: entry.object.translation,
                    rotation: simd_quatf(entry.object.rotation).normalized,
                    scale: entry.object.scale
                )
            )
        }
        controllerRefs = objects.map(\.object.controllerRef)
        for entry in objects {
            try readExtraData(of: entry.block)
        }
    }

    mutating func readControllers() throws {
        for (node, first) in controllerRefs.enumerated() {
            var next = first
            var visited: Set<Int32> = []
            while next >= 0, Int(next) < file.blocks.count, visited.insert(next).inserted {
                let block = file.blocks[Int(next)]
                var reader = BinaryReader(block.data)
                let base = try NIFTimeController(reader: &reader)
                next = base.nextControllerRef
                try read(block, base: base, reader: &reader, node: node)
            }
        }
    }

    private mutating func read(
        _ block: NIFFile.Block, base: NIFTimeController, reader: inout BinaryReader, node: Int
    ) throws {
        switch block.typeName {
        case NIFCameraTrack.controllerTypeName:
            guard !base.isManagerControlled else { return }
            let interpolator = try reader.readNIFRef()
            guard let motion = try motion(interpolator) else { return }
            append(node, block.typeName, base, motion)
        case NIFLagBoneController.typeName:
            var whole = BinaryReader(block.data)
            let lag = try NIFLagBoneController(reader: &whole)
            append(node, block.typeName, base, .lag(NIFLagBone(
                linearVelocity: lag.linearVelocity, linearRotation: lag.linearRotation,
                maximumDistance: lag.maximumDistance
            )))
        case NIFBoneLODController.typeName:
            var whole = BinaryReader(block.data)
            lodController = try NIFBoneLODController(reader: &whole)
        default:
            return
        }
    }

    private mutating func append(
        _ node: Int, _ typeName: String, _ base: NIFTimeController,
        _ motion: NIFNodeAnimation.Motion
    ) {
        controllers.append(NIFNodeAnimation.Controller(
            node: node, typeName: typeName, isActive: base.isActive, timing: base.timing,
            motion: motion
        ))
    }

    /// Keys, a path, or a look-at turn; nil for an interpolator that moves nothing here.
    private func motion(_ ref: Int32) throws -> NIFNodeAnimation.Motion? {
        guard ref >= 0, Int(ref) < file.blocks.count else { return nil }
        let block = file.blocks[Int(ref)]
        let sequences = NIFSequenceDecoder(file: file)
        switch block.typeName {
        case NIFCameraTrack.interpolatorTypeName:
            return try sequences.transform(ref).map(NIFNodeAnimation.Motion.keys)
        case NIFPathInterpolator.typeName:
            return try NIFPath(interpolatorRef: ref, file: file).map(NIFNodeAnimation.Motion.path)
        case NIFLookAtInterpolator.typeName:
            var reader = BinaryReader(block.data)
            let lookAt = try NIFLookAtInterpolator(reader: &reader, header: file.header)
            var target = Int(exactly: lookAt.lookAtRef).flatMap { nodeOfBlock[$0] }
            if target == nil, let name = lookAt.lookAtName {
                target = nodes.firstIndex { $0.name?.caseInsensitiveCompare(name) == .orderedSame }
            }
            return try .lookAt(NIFLookAt(
                target: target, axis: lookAt.lookAxis,
                translation: lookAt.translationInterpolatorRef >= 0
                    ? sequences.pointKeys(lookAt.translationInterpolatorRef) : [],
                roll: NIFParticleControllerDecoder.floatKeys(
                    lookAt.rollInterpolatorRef,
                    file: file
                ),
                scale: NIFParticleControllerDecoder.floatKeys(
                    lookAt.scaleInterpolatorRef,
                    file: file
                )
            ))
        default:
            return nil
        }
    }

    private mutating func readExtraData(of block: Int) throws {
        var reader = BinaryReader(file.blocks[block].data)
        let object = try NIFObjectNET(reader: &reader, header: file.header)
        for ref in object.extraDataRefs where ref >= 0 && Int(ref) < file.blocks.count {
            let extra = file.blocks[Int(ref)]
            guard
                extra.typeName == "BSBoneLODExtraData",
                let value = try NIFBlockDecoders.decode(extra, header: file.header)
                as? NIFExtraData,
                case let .boneLOD(entries) = value.value
            else { continue }
            lodDistances = entries
        }
    }

    func boneLOD() -> NIFBoneLODLevels? {
        guard lodController != nil || !lodDistances.isEmpty else { return nil }
        let levels = (lodController?.nodeGroups ?? []).map { group in
            group.compactMap { Int(exactly: $0).flatMap { nodeOfBlock[$0] } }
        }
        let bones = lodDistances.map { entry in
            NIFBoneLODLevels.Bone(
                distance: Float(entry.distance),
                node: entry.boneName.flatMap { name in
                    nodes.firstIndex { $0.name?.caseInsensitiveCompare(name) == .orderedSame }
                },
                name: entry.boneName
            )
        }
        return NIFBoneLODLevels(levels: levels, bones: bones)
    }
}
