// The shader property controllers that play on their own clock, as a material
// animation. A controller that a manager's sequence feeds is left to the sequence.
// Variable names: nif.xml; layout: docs/formats/nif-controllers.md.

import Foundation
public import OpenSkyFormatsCore

/// One shader property controller of a mesh, for listing and for the material track.
nonisolated public struct NIFShaderControllerEntry: Equatable, Sendable {
    public let shaderBlock: Int
    public let kind: NIFShaderPropertyController.Kind
    public let variable: UInt32
    /// The nif.xml name of `variable`, or nil for a value nif.xml does not name.
    public let variableName: String?
    public let isActive: Bool
    public let isManagerControlled: Bool
    public let timing: ControllerTiming
    public let keyCount: Int
    /// The material value it drives; nil when OpenSky draws no such value.
    public let target: MaterialAnimation.Target?
}

nonisolated public enum NIFShaderAnimation {
    /// Every shader property controller in the file, in block order, then chain order.
    public static func controllers(in file: NIFFile) throws -> [NIFShaderControllerEntry] {
        var entries: [NIFShaderControllerEntry] = []
        for (index, block) in file.blocks.enumerated() where isShaderProperty(block.typeName) {
            entries += try controllers(ofShader: index, file: file).map(\.entry)
        }
        return entries
    }

    /// The material track of one shader property; nil when nothing it draws moves.
    static func animation(ofShader index: Int, file: NIFFile) throws -> MaterialAnimation? {
        let tracks = try controllers(ofShader: index, file: file).compactMap(\.track)
        return tracks.isEmpty ? nil : MaterialAnimation(tracks: tracks)
    }

    static func isShaderProperty(_ typeName: String) -> Bool {
        typeName == "BSEffectShaderProperty" || typeName == "BSLightingShaderProperty"
    }

    private struct Decoded {
        let entry: NIFShaderControllerEntry
        let track: MaterialAnimation.Track?
    }

    private static func controllers(ofShader index: Int, file: NIFFile) throws -> [Decoded] {
        guard file.blocks.indices.contains(index) else { return [] }
        let shader = file.blocks[index]
        guard isShaderProperty(shader.typeName) else { return [] }
        var reader = BinaryReader(shader.data)
        if shader.typeName == "BSLightingShaderProperty" {
            reader.skip(4) // the shader type comes before the NiObjectNET part
        }
        var next = try NIFObjectNET(reader: &reader, header: file.header).controllerRef
        var visited: Set<Int32> = []
        var decoded: [Decoded] = []
        while next >= 0, Int(next) < file.blocks.count, visited.insert(next).inserted {
            let block = file.blocks[Int(next)]
            var controllerReader = BinaryReader(block.data)
            guard let kind = NIFShaderPropertyController.Kind(rawValue: block.typeName) else {
                next = try NIFTimeController(reader: &controllerReader).nextControllerRef
                continue
            }
            let controller = try NIFShaderPropertyController(kind: kind, reader: &controllerReader)
            next = controller.base.controller.nextControllerRef
            try decoded.append(decode(controller, shader: index, file: file))
        }
        return decoded
    }

    private static func decode(
        _ controller: NIFShaderPropertyController, shader: Int, file: NIFFile
    ) throws -> Decoded {
        let base = controller.base.controller
        let interpolator = controller.base.interpolatorRef
        let values: [NIFKey<SIMD3<Float>>] = if controller.kind.isColor {
            try interpolator >= 0 ? NIFFile.SequenceDecoder(file: file).pointKeys(interpolator) : []
        } else {
            try NIFFile.ParticleControllerDecoder.floatKeys(interpolator, file: file)
                .map { NIFKey(time: $0.time, value: SIMD3($0.value, 0, 0)) }
        }
        let target = NIFShaderVariable.target(controller.kind, controller.variable)
        let entry = NIFShaderControllerEntry(
            shaderBlock: shader, kind: controller.kind, variable: controller.variable,
            variableName: NIFShaderVariable.name(controller.kind, controller.variable),
            isActive: base.isActive, isManagerControlled: base.isManagerControlled,
            timing: base.timing, keyCount: values.count, target: target
        )
        let plays = base.isActive && !base.isManagerControlled && values.count > 1
        guard plays, let target else { return Decoded(entry: entry, track: nil) }
        let track = MaterialAnimation.Track(
            target: target, clock: base.timing.clock,
            times: values.map(\.time), values: values.map(\.value)
        )
        return Decoded(entry: entry, track: track)
    }
}

/// nif.xml `EffectShaderControlledVariable`, `EffectShaderControlledColor`,
/// `LightingShaderControlledFloat`, and `LightingShaderControlledColor`.
nonisolated enum NIFShaderVariable {
    typealias Entry = (name: String, target: MaterialAnimation.Target?)

    static let effectFloat: [UInt32: Entry] = [
        0: ("Emissive Multiple", .emissiveMultiple),
        1: ("Falloff Start Angle", .falloffStartAngle),
        2: ("Falloff Stop Angle", .falloffStopAngle),
        3: ("Falloff Start Opacity", .falloffStartOpacity),
        4: ("Falloff Stop Opacity", .falloffStopOpacity),
        5: ("Alpha Transparency", .alpha),
        6: ("U Offset", .uOffset), 7: ("U Scale", .uScale),
        8: ("V Offset", .vOffset), 9: ("V Scale", .vScale)
    ]
    static let effectColor: [UInt32: Entry] = [0: ("Emissive Color", .emissiveColor)]
    static let lightingFloat: [UInt32: Entry] = [
        0: ("Refraction Strength", .refractionStrength),
        8: ("Environment Map Scale", .environmentScale),
        9: ("Glossiness", .glossiness),
        10: ("Specular Strength", .specularStrength),
        11: ("Emissive Multiple", .emissiveMultiple),
        12: ("Alpha", .alpha),
        20: ("U Offset", .uOffset), 21: ("U Scale", .uScale),
        22: ("V Offset", .vOffset), 23: ("V Scale", .vScale)
    ]
    static let lightingColor: [UInt32: Entry] = [
        0: ("Specular Color", .specularColor), 1: ("Emissive Color", .emissiveColor)
    ]

    static func table(_ kind: NIFShaderPropertyController.Kind) -> [UInt32: Entry] {
        switch kind {
        case .effectFloat: effectFloat
        case .effectColor: effectColor
        case .lightingFloat: lightingFloat
        case .lightingColor: lightingColor
        }
    }

    static func name(_ kind: NIFShaderPropertyController.Kind, _ variable: UInt32) -> String? {
        table(kind)[variable]?.name
    }

    static func target(
        _ kind: NIFShaderPropertyController.Kind, _ variable: UInt32
    ) -> MaterialAnimation.Target? {
        table(kind)[variable]?.target
    }
}
