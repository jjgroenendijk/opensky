// What `EffectsCoordinator` asks of the world, the records, and the image-space state,
// kept on those values so the coordinator only routes.

import Foundation
import Metal
import OpenSkyAudio
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyShaderTypes
import OpenSkyWorldInterface
import simd

extension EffectsWorld {
    /// The actor's feet and bones, which its skin decals move with.
    func skinDecalFrames(of key: ReferenceKey) -> SkinDecalFrames {
        SkinDecalFrames(feet: effectTransform(of: key), bones: effectBones(of: key))
    }
}

extension EffectRecordStore {
    /// Starts the `IMAD` `key` on `imageSpace`. False when the record is missing.
    func startModifier(
        _ key: ReferenceKey, on imageSpace: inout ImageSpaceState,
        strength: Float, fade: (looping: Bool, fadeIn: Float)
    ) -> Bool {
        guard let adapter = imageSpaceAdapters.record(key) else { return false }
        imageSpace.modifiers.start(
            adapter.record, key: key, strength: strength, looping: fade.looping,
            fadeIn: fade.fadeIn
        )
        return true
    }

    /// Starts one low-health pulse. Pulses stack, up to the strongest one.
    func startLowHealthPulse(strength: Float, on imageSpace: inout ImageSpaceState) {
        guard
            let key = lowHealthModifier,
            let adapter = imageSpaceAdapters.record(key)
        else { return }
        imageSpace.modifiers.start(
            adapter.record, key: key, strength: strength,
            strengthLimit: PlayerHealthCues.strongestPulse, stacks: true
        )
    }

    /// The load-order sound of `heartbeat`, for the sound director.
    func heartbeatSound(_ heartbeat: Heartbeat) -> FormID? {
        let key = heartbeat == .slow ? slowHeartbeat : fastHeartbeat
        return key.flatMap(loadOrderFormID)
    }
}

extension ImageSpaceState {
    /// Stops every running instance of the `IMAD` `key`, over `fadeOut` seconds.
    mutating func stopModifier(_ key: ReferenceKey, fadeOut: Float) {
        modifiers.stop(key: key, fadeOut: fadeOut)
    }
}

extension ScreenBloodTextures {
    /// The splatter and flare textures `settings` names.
    static func load(from textures: TextureLibrary, settings: BloodEffectSettings) -> Self {
        func load(_ path: String) -> any MTLTexture {
            textures.texture(key: NIFShaderTextureSet.vfsKey(for: path), usage: .color)
        }
        return Self(
            color: load(settings.splatterColorTexture),
            alpha: load(settings.splatterAlphaTexture),
            flare: load(settings.flareTexture)
        )
    }
}

/// The decals as the renderer takes them: one batch per texture and kind.
enum EffectDecalBatches {
    /// `placed` pairs each decal with whether it projects onto skin.
    static func batches(_ placed: [(Decal, Bool)], textures: TextureLibrary) -> [DecalBatch] {
        var order: [DecalBatchKey] = []
        var byKey: [DecalBatchKey: [DecalInstance]] = [:]
        for (decal, projected) in placed {
            let key = DecalBatchKey(texture: decal.look.texture, projected: projected)
            if byKey[key] == nil {
                order.append(key)
            }
            // A skin decal's box reaches as deep as its widest side, to wrap a limb.
            let depth = projected ? max(simd_length(decal.axisU), simd_length(decal.axisV)) : 0
            byKey[key, default: []].append(DecalInstance(
                center: SIMD4(decal.center, depth),
                axisU: SIMD4(decal.axisU, 0),
                axisV: SIMD4(decal.axisV, 0),
                color: SIMD4(decal.look.color, 1),
                uvRect: decal.uvRect
            ))
        }
        return order.map { key in
            DecalBatch(
                texture: textures.texture(key: key.texture, usage: .color),
                instances: byKey[key] ?? [],
                projected: key.projected
            )
        }
    }
}

private struct DecalBatchKey: Hashable {
    let texture: String
    let projected: Bool
}
