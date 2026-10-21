// `nif <key> --sequences`: the effect scene's node tree with full transforms, its
// unlit shapes, and every controller sequence with its tracks and text keys.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import simd

enum NIFSequenceReport {
    static func print(file: NIFFile) {
        do {
            let scene = try NIFEffectScene(file: file)
            printScene(scene)
            for sequence in try file.sequences() {
                printSequence(sequence)
            }
        } catch {
            printError("[WARNING] sequences failed: \(String(describing: error))")
        }
    }

    private static func printScene(_ scene: NIFEffectScene) {
        for (index, node) in scene.nodes.enumerated() {
            let axis = node.rotation.axis
            Swift.print(
                "node \(index) \(node.name ?? "-") parent \(node.parent.map(String.init) ?? "-") "
                    + "t \(format(node.translation)) rot \(format(node.rotation.angle * 180 / .pi))"
                    + " deg about \(format(axis)) scale \(format(node.scale))"
                    + (node.isHidden ? " hidden" : "")
                    + (node.billboardMode.map { " billboard \($0)" } ?? "")
            )
        }
        for shape in scene.shapes {
            let material = shape.material
            let low = shape.positions.reduce(SIMD3(repeating: Float.infinity)) { simd_min($0, $1) }
            let high = shape.positions
                .reduce(SIMD3(repeating: -Float.infinity)) { simd_max($0, $1) }
            Swift.print(
                "shape node \(shape.node) shader \(shape.shaderBlock.map(String.init) ?? "-") "
                    + "\(shape.positions.count) vertices, box \(format(low)) to \(format(high)); "
                    + "texture \(material.sourceTexture ?? "-") palette "
                    + "\(material.shading.paletteTexture ?? "-") colour "
                    + "\(format(material.shading.baseColor)) x "
                    + "\(format(material.shading.baseColorScale)) blend "
                    + (material.blend.map { "\($0.source)/\($0.destination)" } ?? "off")
            )
        }
    }

    private static func printSequence(_ sequence: NIFSequence) {
        let timing = sequence.timing
        Swift.print(
            "sequence \(sequence.name): \(timing.cycle), \(format(timing.startTime)) to "
                + "\(format(timing.stopTime)) s at \(format(timing.frequency)); text keys "
                + sequence.textKeys.map { "\(format($0.time)) \($0.value)" }.joined(separator: ", ")
        )
        for track in sequence.tracks {
            Swift.print("  \(target(track.target)): \(channel(track.channel))")
        }
    }

    private static func target(_ target: NIFSequenceTrack.Target) -> String {
        switch target {
        case let .node(name): "node \(name)"
        case let .shaderProperty(block): "shader block \(block)"
        }
    }

    private static func channel(_ channel: NIFSequenceTrack.Channel) -> String {
        switch channel {
        case let .transform(transform):
            let keys = transform.keys
            return "transform pose t \(transform.translation.map(format) ?? "-") scale "
                + "\(transform.scale.map(format) ?? "-"); keys t "
                + keyList(keys?.translations ?? [], format)
                + " r \(keys?.rotations.count ?? 0) xyz \(keys?.eulerRotations.map(\.count) ?? [])"
                + " s " + keyList(keys?.scales ?? [], format)
        case let .shaderFloat(variable, keys): return "float \(variable) " + keyList(keys, format)
        case let .shaderColor(variable, keys): return "colour \(variable) " + keyList(keys, format)
        case let .visibility(keys): return "visible " + keyList(keys) { $0 ? "on" : "off" }
        case let .alphaTestReference(keys): return "alpha test " + keyList(keys, format)
        case let .extraDataFloat(name, keys): return "extra data \(name) " + keyList(keys, format)
        }
    }

    private static func keyList<Value>(
        _ keys: [NIFKey<Value>], _ text: (Value) -> String
    ) -> String {
        keys.isEmpty ? "none" : keys.map { "\(format($0.time))=\(text($0.value))" }
            .joined(separator: " ")
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.3f", value)
    }

    private static func format<Vector: SIMD>(_ value: Vector) -> String
        where Vector.Scalar == Float
    {
        "(" + value.indices.map { format(value[$0]) }.joined(separator: ", ") + ")"
    }
}
