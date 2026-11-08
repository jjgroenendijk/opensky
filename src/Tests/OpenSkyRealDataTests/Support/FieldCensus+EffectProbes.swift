// The probe lists behind `FieldCensus+Effects.swift`, and the sound records.

import Foundation
@testable import OpenSkyFormatsESM

extension FieldCensus {
    mutating func countOutputModel(_ model: SoundOutputModel) {
        count("SOPM", model, [
            ("formID", { $0.formID }), ("editorID", { $0.editorID }), ("flags", { $0.flags }),
            ("reverbSendPercent", { $0.reverbSendPercent }), ("type", { $0.type }),
            ("channelMatrix", { $0.channelMatrix }), ("attenuation", { $0.attenuation }),
            ("leftovers", { $0.leftovers })
        ])
        count("SOPM attenuation", model.attenuation, [
            ("minimumDistance", { $0.minimumDistance }),
            ("maximumDistance", { $0.maximumDistance }), ("curve", { $0.curve })
        ])
        tally("SOPM", model.skipped)
    }

    mutating func countReverb(_ reverb: ReverbParameters) {
        count("REVB", reverb, [("formID", { $0.formID }), ("editorID", { $0.editorID })])
        count("REVB data", reverb.properties, [
            ("hfReferenceHertz", { $0.hfReferenceHertz }), ("roomHFFilter", { $0.roomHFFilter }),
            ("reflections", { $0.reflections }), ("reverbAmplitude", { $0.reverbAmplitude }),
            ("reflectDelay", { $0.reflectDelay }),
            ("reverbDelayMilliseconds", { $0.reverbDelayMilliseconds }),
            ("diffusionPercent", { $0.diffusionPercent }), ("unknown", { $0.unknown })
        ])
        tally("REVB", reverb.skipped)
    }

    static var materialProperties: [Probe<MaterialObject.Properties>] {
        [
            ("falloffScale", { $0.falloffScale }), ("falloffBias", { $0.falloffBias }),
            ("noiseUVScale", { $0.noiseUVScale }), ("materialUVScale", { $0.materialUVScale }),
            ("projectionVector", { $0.projectionVector }), (
                "normalDampener",
                { $0.normalDampener }
            ),
            ("singlePassColor", { $0.singlePassColor }), ("isSinglePass", { $0.isSinglePass }),
            ("isSnow", { $0.isSnow }), ("size", { $0.size })
        ]
    }

    static var particleProperties: [Probe<ShaderParticleGeometry.Properties>] {
        [
            ("rotationVelocity", { $0.rotationVelocity }),
            ("centerOffsetMinimum", { $0.centerOffsetMinimum }),
            ("centerOffsetMaximum", { $0.centerOffsetMaximum }),
            ("initialRotationRange", { $0.initialRotationRange }),
            ("subtextureCount", { $0.subtextureCount }), ("type", { $0.type }),
            ("particleDensity", { $0.particleDensity }), ("size", { $0.size })
        ]
    }

    static var volumetricLighting: [Probe<VolumetricLighting>] {
        [
            ("formID", { $0.formID }), ("editorID", { $0.editorID }), (
                "intensity",
                { $0.intensity }
            ),
            ("customColorContribution", { $0.customColorContribution }), ("color", { $0.color }),
            ("densityContribution", { $0.densityContribution }), (
                "densitySize",
                { $0.densitySize }
            ),
            ("densityWindSpeed", { $0.densityWindSpeed }),
            ("densityFallingSpeed", { $0.densityFallingSpeed }),
            ("phaseFunctionContribution", { $0.phaseFunctionContribution }),
            ("phaseFunctionScattering", { $0.phaseFunctionScattering }),
            ("samplingRangeFactor", { $0.samplingRangeFactor })
        ]
    }

    static var explosionProperties: [Probe<Explosion.Properties>] {
        [
            ("sound1", { $0.sound1 }), ("sound2", { $0.sound2 }),
            ("impactDataSet", { $0.impactDataSet }), ("placedObject", { $0.placedObject }),
            ("spawnProjectile", { $0.spawnProjectile }), ("force", { $0.force }),
            ("damage", { $0.damage }), ("imageSpaceRadius", { $0.imageSpaceRadius }),
            ("flags", { $0.flags })
        ]
    }
}
