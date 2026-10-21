// The animated `NiCamera` of a CAMS camera mesh. Vanilla cameras animate the
// root node above the camera, so the track is the nearest animated ancestor's
// keys with the camera's offset below it. Layout: docs/formats/nif.md#camera-animation.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct NIFCameraTrack: Equatable, Sendable {
    public static let cameraTypeName = "NiCamera"
    public static let controllerTypeName = "NiTransformController"
    public static let interpolatorTypeName = "NiTransformInterpolator"

    /// The animated node's transform with no animation: the camera itself when
    /// nothing above it moves.
    public let restTranslation: SIMD3<Float>
    public let restRotation: simd_quatf
    /// The camera's transform relative to the animated node.
    public let offsetTranslation: SIMD3<Float>
    public let offsetRotation: simd_quatf
    /// The controller's play window, seconds. Zero for a camera with no keys.
    public let startTime: Float
    public let stopTime: Float
    /// Nil when neither the camera nor a node above it has a transform controller.
    public let keys: NIFTransformData?
    /// Set when an `NiPathInterpolator` moves the animated node instead of keys.
    public let path: NIFCameraPath?
    /// Horizontal field of view from the frustum, radians.
    public let horizontalFieldOfView: Float
    /// The camera's `BSFrustumFOVController` keys; nil keeps the frustum's view.
    public let fieldOfView: NIFFieldOfViewTrack?

    /// The first `NiCamera` in the file. Throws when the file has no camera or
    /// a link in the controller chain is broken.
    public init(file: NIFFile) throws {
        guard
            let cameraIndex = file.blocks
                .firstIndex(where: { $0.typeName == Self.cameraTypeName })
        else {
            throw NIFError.malformed("no NiCamera block")
        }
        var reader = BinaryReader(file.blocks[cameraIndex].data)
        let camera = try NIFObjectPrefix(reader: &reader, header: file.header)
        reader.skip(2) // camera flags
        let left = try reader.readFloat32()
        let right = try reader.readFloat32()
        reader.skip(8) // frustum top, bottom
        let near = try reader.readFloat32()
        horizontalFieldOfView = near > 0 ? atan((right - left) / 2 / near) * 2 : 0
        fieldOfView = try NIFFieldOfViewTrack(controllerRef: camera.controllerRef, file: file)

        // Walk up from the camera; each node passed on the way adds to the offset.
        let parents = Self.parents(file)
        var node = (index: cameraIndex, object: camera)
        var offset = (
            translation: SIMD3<Float>.zero,
            rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        )
        var visited: Set<Int> = []
        while visited.insert(node.index).inserted {
            if let controller = try Self.controller(node.object.controllerRef, file) {
                startTime = controller.start
                stopTime = controller.stop
                keys = try Self.data(of: controller.interpolator, file)
                path = try NIFCameraPath(interpolatorRef: controller.interpolator, file: file)
                restTranslation = node.object.translation
                restRotation = simd_quatf(node.object.rotation)
                offsetTranslation = offset.translation
                offsetRotation = offset.rotation
                return
            }
            guard let parent = parents[node.index] else { break }
            let rotation = simd_quatf(node.object.rotation)
            offset = (
                node.object.translation + rotation.act(offset.translation),
                rotation * offset.rotation
            )
            node = parent
        }
        startTime = 0
        stopTime = 0
        keys = nil
        path = nil
        let top = simd_quatf(node.object.rotation)
        restTranslation = node.object.translation + top.act(offset.translation)
        restRotation = top * offset.rotation
        offsetTranslation = .zero
        offsetRotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    }

    /// Each traversed node's parent, by block index.
    private static func parents(_ file: NIFFile) -> [Int: (index: Int, object: NIFObjectPrefix)] {
        var parents: [Int: (index: Int, object: NIFObjectPrefix)] = [:]
        for (index, block) in file.blocks.enumerated()
            where NIFNode.traversedTypes.contains(block.typeName)
        {
            guard let node = try? NIFNode(data: block.data, header: file.header) else { continue }
            for child in node.children where child >= 0 {
                parents[Int(child)] = (index, node.object)
            }
        }
        return parents
    }

    /// The first transform controller on the chain from `ref`, with its start and
    /// stop times and interpolator ref. Vanilla cameras put a `BSFrustumFOVController` first.
    private struct TransformController {
        let start: Float
        let stop: Float
        let interpolator: Int32
    }

    private static func controller(
        _ ref: Int32,
        _ file: NIFFile
    ) throws -> TransformController? {
        var next = ref
        var visited: Set<Int32> = []
        while next >= 0, Int(next) < file.blocks.count, visited.insert(next).inserted {
            let block = file.blocks[Int(next)]
            var reader = BinaryReader(block.data)
            if block.typeName == controllerTypeName {
                return try transformController(&reader)
            }
            next = try Int32(bitPattern: reader.readUInt32())
        }
        return nil
    }

    private static func transformController(
        _ reader: inout BinaryReader
    ) throws -> TransformController {
        reader.skip(4 + 2 + 4 + 4) // next controller, flags, frequency, phase
        let start = try reader.readFloat32()
        let stop = try reader.readFloat32()
        reader.skip(4) // target
        let interpolator = try Int32(bitPattern: reader.readUInt32())
        return TransformController(start: start, stop: stop, interpolator: interpolator)
    }

    private static func data(
        of interpolatorRef: Int32,
        _ file: NIFFile
    ) throws -> NIFTransformData? {
        guard let block = block(interpolatorRef, file, type: interpolatorTypeName) else {
            return nil
        }
        var reader = BinaryReader(block.data)
        reader.skip(12 + 16 + 4) // NiQuatTransform: translation, rotation, scale
        let dataRef = try Int32(bitPattern: reader.readUInt32())
        guard let data = Self.block(dataRef, file, type: NIFTransformData.typeName) else {
            return nil
        }
        return try NIFTransformData(data: data.data)
    }

    private static func block(_ ref: Int32, _ file: NIFFile, type: String) -> NIFFile.Block? {
        guard ref >= 0, Int(ref) < file.blocks.count else { return nil }
        let block = file.blocks[Int(ref)]
        return block.typeName == type ? block : nil
    }
}

nonisolated extension NIFCameraTrack {
    /// The camera's translation in the mesh at `time` seconds.
    public func translation(at time: Float) -> SIMD3<Float> {
        let node = path?.position(at: time)
            ?? NIFKeySampler.vector(keys?.translations ?? [], at: time) ?? restTranslation
        return node + nodeRotation(at: time).act(offsetTranslation)
    }

    /// The camera's rotation in the mesh at `time` seconds.
    public func rotation(at time: Float) -> simd_quatf {
        nodeRotation(at: time) * offsetRotation
    }

    /// The horizontal field of view at `time` seconds, radians.
    public func horizontalFieldOfView(at time: Float) -> Float {
        fieldOfView?.horizontalFieldOfView(at: time) ?? horizontalFieldOfView
    }

    private func nodeRotation(at time: Float) -> simd_quatf {
        keys?.rotation(at: time) ?? restRotation
    }
}
