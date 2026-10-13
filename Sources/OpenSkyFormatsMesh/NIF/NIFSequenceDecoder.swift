// Reads one `NiControllerSequence` with its interpolators, keys, and text keys.
// Layout: docs/formats/nif-sequences.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated struct NIFSequenceDecoder {
    static let transformControllers: Set = [
        "NiTransformController", "NiMultiTargetTransformController", "NiKeyframeController"
    ]
    /// `NiTimeController` before the interpolator ref: next, flags, frequency,
    /// phase, start, stop, target.
    static let timeControllerSize = 4 + 2 + 4 * 4 + 4

    let file: NIFFile

    func sequence(_ block: NIFFile.Block) throws -> NIFSequence {
        var reader = BinaryReader(block.data)
        let name = try string(&reader) ?? ""
        let count = try Int(reader.readUInt32())
        reader.skip(4) // array grow by
        guard count <= reader.bytesRemaining / Self.controlledBlockSize else {
            throw NIFError.malformed("sequence has \(count) controlled blocks, too many")
        }
        var tracks: [NIFSequenceTrack] = []
        for _ in 0 ..< count {
            let controlled = try ControlledBlock(reader: &reader, decoder: self)
            if let track = try track(controlled) {
                tracks.append(track)
            }
        }
        reader.skip(4) // weight
        let textKeys = try textKeys(Int32(bitPattern: reader.readUInt32()))
        let cycle = try reader.readUInt32()
        let timing = try ControllerTiming(
            cycle: ControllerCycle(rawValue: UInt16(truncatingIfNeeded: cycle)) ?? .clamp,
            frequency: reader.readFloat32(),
            phase: 0,
            startTime: reader.readFloat32(),
            stopTime: reader.readFloat32()
        )
        return NIFSequence(name: name, timing: timing, textKeys: textKeys, tracks: tracks)
    }

    /// Interpolator, controller, priority byte, five string indices.
    static let controlledBlockSize = 4 + 4 + 1 + 5 * 4

    struct ControlledBlock {
        let interpolator: Int32
        let controller: Int32
        let nodeName: String?
        let controllerType: String?
        let controllerID: String?

        init(reader: inout BinaryReader, decoder: NIFSequenceDecoder) throws {
            interpolator = try Int32(bitPattern: reader.readUInt32())
            controller = try Int32(bitPattern: reader.readUInt32())
            reader.skip(1) // priority
            nodeName = try decoder.string(&reader)
            _ = try decoder.string(&reader) // property type
            controllerType = try decoder.string(&reader)
            controllerID = try decoder.string(&reader)
            _ = try decoder.string(&reader) // interpolator ID
        }
    }

    /// Nil for a controller type OpenSky does not play, or an empty interpolator.
    private func track(_ controlled: ControlledBlock) throws -> NIFSequenceTrack? {
        guard controlled.interpolator >= 0 else { return nil }
        let controller = controlled.controller >= 0
            ? try NIFParticleControllerDecoder.block(controlled.controller, file) : nil
        guard let type = controller?.typeName ?? controlled.controllerType else { return nil }
        let node = NIFSequenceTrack.Target.node(controlled.nodeName ?? "")
        if Self.transformControllers.contains(type) {
            return try transform(controlled.interpolator).map {
                NIFSequenceTrack(target: node, channel: .transform($0))
            }
        }
        if type == "NiVisController" {
            let keys = try NIFParticleControllerDecoder.boolKeys(
                controlled.interpolator,
                file: file
            )
            return NIFSequenceTrack(target: node, channel: .visibility(keys))
        }
        let isFloat = type.hasSuffix("ShaderPropertyFloatController")
        guard isFloat || type.hasSuffix("ShaderPropertyColorController") else { return nil }
        var variable = controlled.controllerID.flatMap { UInt32($0) } ?? 0
        var target = node
        if let controller {
            var reader = BinaryReader(controller.data)
            reader.skip(Self.timeControllerSize - 4)
            let property = try Int32(bitPattern: reader.readUInt32())
            reader.skip(4) // interpolator
            variable = try reader.readUInt32()
            if property >= 0 {
                target = .shaderProperty(block: Int(property))
            }
        }
        if isFloat {
            let keys = try NIFParticleControllerDecoder.floatKeys(
                controlled.interpolator,
                file: file
            )
            return NIFSequenceTrack(
                target: target,
                channel: .shaderFloat(variable: variable, keys: keys)
            )
        }
        let keys = try colorKeys(controlled.interpolator)
        return NIFSequenceTrack(
            target: target,
            channel: .shaderColor(variable: variable, keys: keys)
        )
    }

    /// `NiTransformInterpolator`: translation, rotation (w first), scale, then a
    /// `NiTransformData` ref. A part equal to `#INV_FLT#` is unset.
    private func transform(_ ref: Int32) throws -> NIFTransformChannel? {
        let block = try NIFParticleControllerDecoder.block(ref, file)
        guard block.typeName == "NiTransformInterpolator" else { return nil }
        var reader = BinaryReader(block.data)
        let translation = try reader.readVector3()
        let rotation = try NIFTransformData.readQuaternion(&reader)
        let scale = try reader.readFloat32()
        let dataRef = try Int32(bitPattern: reader.readUInt32())
        var keys: NIFTransformData?
        if dataRef >= 0 {
            let data = try NIFParticleControllerDecoder.block(dataRef, file)
            guard data.typeName == NIFTransformData.typeName else {
                throw NIFError.malformed("transform interpolator data is \(data.typeName)")
            }
            keys = try NIFTransformData(data: data.data)
        }
        return NIFTransformChannel(
            translation: Self.isSet(translation.x) ? translation : nil,
            rotation: Self.isSet(rotation.real) ? rotation : nil,
            scale: Self.isSet(scale) ? scale : nil,
            keys: keys
        )
    }

    /// `NiPoint3Interpolator`: a pose, then a `NiPosData` ref.
    private func colorKeys(_ ref: Int32) throws -> [NIFKey<SIMD3<Float>>] {
        let block = try NIFParticleControllerDecoder.block(ref, file)
        guard block.typeName == "NiPoint3Interpolator" else { return [] }
        var reader = BinaryReader(block.data)
        let value = try reader.readVector3()
        let dataRef = try Int32(bitPattern: reader.readUInt32())
        guard dataRef >= 0 else {
            return Self.isSet(value.x) ? [NIFKey(time: 0, value: value)] : []
        }
        let data = try NIFParticleControllerDecoder.block(dataRef, file)
        guard data.typeName == "NiPosData" else {
            throw NIFError.malformed("point interpolator data is \(data.typeName)")
        }
        var keys = BinaryReader(data.data)
        return try NIFTransformData.keyGroup(&keys, keySize: 16) { try $0.readVector3() }
    }

    /// `NiTextKeyExtraData`: name, then a count of time and string pairs.
    private func textKeys(_ ref: Int32) throws -> [NIFKey<String>] {
        guard ref >= 0 else { return [] }
        let block = try NIFParticleControllerDecoder.block(ref, file)
        guard block.typeName == "NiTextKeyExtraData" else { return [] }
        var reader = BinaryReader(block.data)
        _ = try string(&reader)
        let count = try Int(reader.readUInt32())
        guard count * 8 <= reader.bytesRemaining else {
            throw NIFError.malformed("text key count \(count) exceeds block size")
        }
        return try (0 ..< count).compactMap { _ in
            let time = try reader.readFloat32()
            return try string(&reader).map { NIFKey(time: time, value: $0) }
        }
    }

    private static func isSet(_ value: Float) -> Bool {
        value.isFinite && value != NIFParticleControllerDecoder.invalidFloat
    }

    func string(_ reader: inout BinaryReader) throws -> String? {
        let index = try reader.readUInt32()
        return index != .max && Int(index) < file.header.strings.count
            ? file.header.strings[Int(index)] : nil
    }
}
