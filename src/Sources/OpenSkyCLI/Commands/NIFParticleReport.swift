// `nif <key> --sequences`: each particle system's emitters, modifiers, blend, and atlas
// frames, so a smoke or fire can be checked against the game without a renderer.

import Foundation
import OpenSkyFormatsMesh
import simd

enum NIFParticleReport {
    static func print(file: NIFFile) {
        do {
            for system in try file.particleSystems() {
                printSystem(system)
            }
        } catch {
            printError("[WARNING] particle systems failed: \(String(describing: error))")
        }
    }

    private static func printSystem(_ system: ParticleSystemDefinition) {
        let alpha = system.alphaProperty
        Swift.print(
            "particle system \(system.name ?? "-") max \(system.maxParticles) "
                + "world space \(system.worldSpace) strip \(system.isStrip) "
                + "blend \(alpha.map { "\($0.sourceBlendMode)/\($0.destinationBlendMode)" } ?? "-")"
        )
        if let shading = system.effectShader?.shading {
            Swift.print("  shading \(String(describing: shading))")
        }
        for emitter in system.emitters {
            Swift.print(
                "  emitter \(emitter.name ?? "-") speed \(emitter.speed)±\(emitter.speedVariation) "
                    + "radius \(emitter.initialRadius)±\(emitter.radiusVariation) "
                    + "life \(emitter.lifeSpan)±\(emitter.lifeSpanVariation) "
                    + "colour \(NIFSequenceReport.format(emitter.initialColor)) "
                    + "declination \(emitter.declination)±\(emitter.declinationVariation)"
            )
        }
        for modifier in system.modifiers {
            Swift.print("  modifier \(String(describing: modifier))")
        }
        printFrames(system.subtextureOffsets)
    }

    /// The atlas frames as u, v, width, height, with the distinct frame sizes.
    private static func printFrames(_ offsets: [SIMD4<Float>]) {
        guard !offsets.isEmpty else { return }
        let sizes = Set(offsets.map { "\($0.z)x\($0.w)" })
        Swift.print("  atlas frames \(offsets.count), sizes \(sizes.sorted())")
        for (index, rect) in offsets.enumerated() {
            Swift.print("  frame \(index) \(NIFSequenceReport.format(rect))")
        }
    }
}
