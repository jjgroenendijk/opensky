// The presentation links a landed spell names through its MGEF records: the
// image-space modifier, the hit shader, the hit effect art, and the explosion.
// The magic coordinator reports them; the effects adapter acts on them.
// See docs/rendering/visual-effects.md.

import OpenSkyFormatsESM
import OpenSkyGameData

/// One MGEF's presentation links, still raw and written in `plugin`.
nonisolated public struct SpellHitEffectLinks: Equatable, Sendable {
    /// The plugin the links below are written in: the MGEF's own.
    public let plugin: String
    public let imageSpaceModifier: FormID?
    public let hitShader: FormID?
    public let hitEffectArt: FormID?
    public let explosion: FormID?
    /// The spell entry's area, feet. A non-zero area sets off the explosion.
    public let area: UInt32
    /// The spell entry's duration, seconds. Zero means the hit is instant.
    public let duration: UInt32

    public init(
        plugin: String,
        imageSpaceModifier: FormID? = nil,
        hitShader: FormID? = nil,
        hitEffectArt: FormID? = nil,
        explosion: FormID? = nil,
        area: UInt32 = 0,
        duration: UInt32 = 0
    ) {
        self.plugin = plugin
        self.imageSpaceModifier = imageSpaceModifier
        self.hitShader = hitShader
        self.hitEffectArt = hitEffectArt
        self.explosion = explosion
        self.area = area
        self.duration = duration
    }
}

/// One landed spell, after its effects were applied.
nonisolated public struct SpellHitEvent: Equatable, Sendable {
    public let hit: SpellHit
    public let links: [SpellHitEffectLinks]

    public init(hit: SpellHit, links: [SpellHitEffectLinks]) {
        self.hit = hit
        self.links = links
    }
}

nonisolated extension MagicEffectStore {
    /// The links of every entry in `payload` whose MGEF resolves.
    public func hitEffectLinks(of payload: SpellPayload) -> [SpellHitEffectLinks] {
        payload.entries.compactMap { entry -> SpellHitEffectLinks? in
            guard
                let resolved = resolve(entry, fromPlugin: payload.sourcePlugin),
                let effect = resolved.effect.data
            else { return nil }
            return SpellHitEffectLinks(
                plugin: resolved.sourcePlugin,
                imageSpaceModifier: effect.imageSpaceModifier,
                hitShader: effect.hitShader,
                hitEffectArt: effect.hitEffectArt,
                explosion: effect.explosion,
                area: entry.area,
                duration: entry.duration
            )
        }
    }
}
