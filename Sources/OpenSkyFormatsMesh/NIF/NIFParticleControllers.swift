// The `NiPSysEmitterCtlr` blocks on a particle system's controller chain and
// the float and bool interpolators they read. Other controllers are passed
// over. Layout: docs/formats/nif-particles.md.

import Foundation
import OpenSkyFormatsCore

nonisolated enum NIFParticleControllerDecoder {
    static let emitterControllerType = "NiPSysEmitterCtlr"
    static let boolInterpolatorTypes: Set = ["NiBoolInterpolator", "NiBoolTimelineInterpolator"]
    /// nif.xml `#INV_FLT#`: the pose value is unset.
    static let invalidFloat: Float = -3.402823466e+38

    /// Every emitter controller from `ref` along the next-controller links.
    static func emitterControllers(
        from ref: Int32,
        file: NIFFile
    ) throws -> [ParticleEmitterController] {
        var controllers: [ParticleEmitterController] = []
        var next = ref
        var visited: Set<Int32> = []
        while next >= 0 {
            guard visited.insert(next).inserted else {
                throw NIFError.malformed("controller chain loops at block \(next)")
            }
            let block = try Self.block(next, file)
            var reader = BinaryReader(block.data)
            next = try Int32(bitPattern: reader.readUInt32())
            if block.typeName == emitterControllerType {
                try controllers.append(emitterController(&reader, file: file))
            }
        }
        return controllers
    }

    /// Reads past the next-controller ref, which the caller has already read.
    private static func emitterController(
        _ reader: inout BinaryReader,
        file: NIFFile
    ) throws -> ParticleEmitterController {
        let flags = try reader.readUInt16()
        let frequency = try reader.readFloat32()
        let phase = try reader.readFloat32()
        let start = try reader.readFloat32()
        let stop = try reader.readFloat32()
        reader.skip(4) // target
        let interpolator = try Int32(bitPattern: reader.readUInt32())
        let nameIndex = try reader.readUInt32()
        let visibility = try Int32(bitPattern: reader.readUInt32())
        let name = nameIndex != .max && Int(nameIndex) < file.header.strings.count
            ? file.header.strings[Int(nameIndex)] : nil
        return try ParticleEmitterController(
            modifierName: name,
            timing: ControllerTiming(
                cycle: ControllerCycle(rawValue: (flags >> 1) & 0x3) ?? .clamp,
                frequency: frequency,
                phase: phase,
                startTime: start,
                stopTime: stop
            ),
            birthRate: floatKeys(interpolator, file: file),
            active: boolKeys(visibility, file: file)
        )
    }

    /// `NiFloatInterpolator`: pose value, then a `NiFloatData` ref. Another
    /// interpolator type (a blend from a controller manager) gives no keys.
    private static func floatKeys(_ ref: Int32, file: NIFFile) throws -> [NIFKey<Float>] {
        guard ref >= 0 else { return [] }
        let block = try Self.block(ref, file)
        guard block.typeName == "NiFloatInterpolator" else { return [] }
        var reader = BinaryReader(block.data)
        let value = try reader.readFloat32()
        let dataRef = try Int32(bitPattern: reader.readUInt32())
        if dataRef >= 0 {
            let data = try Self.block(dataRef, file)
            guard data.typeName == "NiFloatData" else {
                throw NIFError.malformed("float interpolator data is \(data.typeName)")
            }
            var keys = BinaryReader(data.data)
            return try NIFTransformData.keyGroup(&keys) { try $0.readFloat32() }
        }
        return value == invalidFloat || !value.isFinite ? [] : [NIFKey(time: 0, value: value)]
    }

    /// `NiBoolInterpolator` or `NiBoolTimelineInterpolator`: pose byte (2 is unset),
    /// then a `NiBoolData` ref.
    private static func boolKeys(_ ref: Int32, file: NIFFile) throws -> [NIFKey<Bool>] {
        guard ref >= 0 else { return [] }
        let block = try Self.block(ref, file)
        guard boolInterpolatorTypes.contains(block.typeName) else { return [] }
        var reader = BinaryReader(block.data)
        let value = try reader.readUInt8()
        let dataRef = try Int32(bitPattern: reader.readUInt32())
        if dataRef >= 0 {
            let data = try Self.block(dataRef, file)
            guard data.typeName == "NiBoolData" else {
                throw NIFError.malformed("bool interpolator data is \(data.typeName)")
            }
            var keys = BinaryReader(data.data)
            return try NIFTransformData.keyGroup(&keys, keySize: 5) { try $0.readUInt8() != 0 }
        }
        return value > 1 ? [] : [NIFKey(time: 0, value: value == 1)]
    }

    private static func block(_ ref: Int32, _ file: NIFFile) throws -> NIFFile.Block {
        guard ref >= 0, Int(ref) < file.blocks.count else {
            throw NIFError.malformed("block ref \(ref) out of range (\(file.blocks.count) blocks)")
        }
        return file.blocks[Int(ref)]
    }
}
