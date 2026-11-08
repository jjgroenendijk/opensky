// Census probes for visual, sound, and camera records.

import Foundation
@testable import OpenSkyFormatsESM

extension FieldCensus {
    mutating func countCameraShot(_ shot: CameraShot) {
        count("CAMS", shot, [
            ("formID", { $0.formID }), ("model", { $0.model }), ("dataSize", { $0.dataSize })
        ])
        count("CAMS data", shot.properties, [
            ("location", { $0.location }), ("target", { $0.target }),
            ("timeMultipliers", { $0.timeMultipliers }), ("maxTime", { $0.maxTime }),
            ("minTime", { $0.minTime }),
            ("targetPercentBetweenActors", { $0.targetPercentBetweenActors })
        ])
        tally("CAMS", shot.skipped)
    }

    mutating func countCameraPath(_ path: CameraPath) {
        count("CPTH", path, [("formID", { $0.formID }), ("conditions", { $0.conditions })])
        tally("CPTH", path.skipped)
    }

    mutating func countEffectShader(_ shader: EffectShader) {
        count("EFSH", shader, [
            ("editorID", { $0.editorID }), ("particleTexture", { $0.particleTexture }),
            ("holesTexture", { $0.holesTexture }),
            ("membranePaletteTexture", { $0.membranePaletteTexture }),
            ("particlePaletteTexture", { $0.particlePaletteTexture })
        ])
        tally("EFSH", shader.skipped)
    }

    mutating func countMaterial(_ material: MaterialObject) {
        count("MATO", material, [
            ("formID", { $0.formID }), ("editorID", { $0.editorID }), ("model", { $0.model }),
            ("propertyData", { $0.propertyData }), ("properties", { $0.properties })
        ])
        count("MATO data", material.properties, Self.materialProperties)
        tally("MATO", material.skipped)
    }

    mutating func countParticles(_ geometry: ShaderParticleGeometry) {
        count("SPGD", geometry, [("formID", { $0.formID }), ("editorID", { $0.editorID })])
        count("SPGD data", geometry.properties, Self.particleProperties)
        tally("SPGD", geometry.skipped)
    }

    mutating func countVolumetricLighting(_ lighting: VolumetricLighting) {
        count("VOLI", lighting, Self.volumetricLighting)
        tally("VOLI", lighting.skipped)
    }

    mutating func countDebris(_ debris: Debris) {
        count("DEBR", debris, [("formID", { $0.formID }), ("editorID", { $0.editorID })])
        count("DEBR model", debris.models, [("percentage", { $0.percentage })])
        tally("DEBR", debris.skipped)
    }

    mutating func countExplosion(_ explosion: Explosion) {
        count("EXPL", explosion, [
            ("formID", { $0.formID }), ("editorID", { $0.editorID }), ("bounds", { $0.bounds }),
            ("name", { $0.name }), ("model", { $0.model }),
            ("imageSpaceModifier", { $0.imageSpaceModifier }),
            ("scriptData", { $0.scriptData.scripts })
        ])
        count("EXPL data", explosion.properties, Self.explosionProperties)
        tally("EXPL", explosion.skipped)
    }

    mutating func countImageSpace(_ space: ImageSpace) {
        count("IMGS", space, [("formID", { $0.formID }), ("editorID", { $0.editorID })])
        count("IMGS HDR", space.hdr, [
            ("bloomBlurRadius", { $0.bloomBlurRadius }), ("bloomThreshold", { $0.bloomThreshold }),
            ("bloomScale", { $0.bloomScale }),
            ("receiveBloomThreshold", { $0.receiveBloomThreshold }), ("white", { $0.white }),
            ("sunlightScale", { $0.sunlightScale }), ("skyScale", { $0.skyScale })
        ])
        count("IMGS cinematic", space.cinematic, [
            ("saturation", { $0.saturation }), ("contrast", { $0.contrast })
        ])
        count("IMGS tint", space.tint, [("amount", { $0.amount })])
        count("IMGS depth of field", space.depthOfField, [
            ("strength", { $0.strength }), ("distance", { $0.distance })
        ])
        tally("IMGS", space.skipped)
    }

    mutating func countImageSpaceAdapter(_ adapter: ImageSpaceAdapter) {
        count("IMAD", adapter, [("formID", { $0.formID }), ("editorID", { $0.editorID })])
        count("IMAD header", adapter.header, [
            ("isAnimatable", { $0.isAnimatable }),
            ("radialBlurUsesTarget", { $0.radialBlurUsesTarget }),
            ("radialBlurCenter", { $0.radialBlurCenter }),
            ("depthOfFieldUsesTarget", { $0.depthOfFieldUsesTarget }),
            ("depthOfFieldFlags", { $0.depthOfFieldFlags })
        ])
        count("IMAD key", adapter.envelopes.values.flatMap(\.self), [("time", { $0.time })])
        count("IMAD color key", adapter.tint + adapter.fade, [
            ("time", { $0.time }), ("color", { $0.color })
        ])
        tally("IMAD", adapter.skipped)
    }

    mutating func countVisualEffect(_ effect: VisualEffect) {
        count("RFCT", effect, [("formID", { $0.formID }), ("editorID", { $0.editorID })])
        tally("RFCT", effect.skipped)
    }

    mutating func countAddonNode(_ node: AddonNode) {
        count("ADDN", node, [
            ("formID", { $0.formID }), ("editorID", { $0.editorID }), ("bounds", { $0.bounds }),
            ("model", { $0.model }), ("sound", { $0.sound })
        ])
        tally("ADDN", node.skipped)
    }

    mutating func countHazard(_ hazard: Hazard) {
        count("HAZD", hazard, [
            ("formID", { $0.formID }), ("bounds", { $0.bounds }), ("name", { $0.name })
        ])
        count("HAZD data", hazard.properties, [
            ("lifetime", { $0.lifetime }), ("imageSpaceRadius", { $0.imageSpaceRadius }),
            ("targetInterval", { $0.targetInterval }),
            ("inheritsDurationFromSpell", { $0.inheritsDurationFromSpell }),
            ("inheritsRadiusFromSpell", { $0.inheritsRadiusFromSpell })
        ])
        tally("HAZD", hazard.skipped)
    }
}
