// The presentation links a landed spell names through its MGEF records: the
// image-space modifier, the hit shader, the hit effect art, and the explosion.
// The magic coordinator reports them; the effects adapter acts on them.
// See docs/rendering/visual-effects.md.

public import OpenSkyFormatsESM
public import OpenSkyGameData

/// One MGEF's presentation links, still raw and written in `plugin`.
nonisolated public struct SpellHitEffectLinks: Equatable, Sendable {
    /// The plugin the links below are written in: the MGEF's own.
    public let plugin: String
    public let imageSpaceModifier: FormID?
    public let hitShader: FormID?
    public let hitEffectArt: FormID?
    public let explosion: FormID?
    /// The MGEF's On Hit sound, a load-order `SNDR`: it "plays when this effect is
    /// applied to its target" (CK wiki "Magic Effect").
    public var hitSound: FormID?
    /// The spell entry's area, feet. A non-zero area sets off the explosion.
    public let area: UInt32
    /// The spell entry's duration, seconds. Zero means the hit is instant.
    public let duration: UInt32
    /// An Absorb effect, whose instant hit visual lasts `fMagicAbsorbVisualTimer`.
    public var isAbsorb = false
    /// The spell's main effect, the only one whose explosion goes off.
    public var isMain = false

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
    /// `SNDD` kind 5, On Hit (UESP "Skyrim Mod:Mod File Format/MGEF").
    static let onHitSoundKind: UInt32 = 5

    /// The links of every entry in `payload` whose MGEF resolves, the main one marked.
    public func hitEffectLinks(of payload: SpellPayload) -> [SpellHitEffectLinks] {
        let effects = resolvedEffects(
            payload.entries, fromPlugin: payload.sourcePlugin, castingType: .fireAndForget
        )
        let main = MainMagicEffect.index(of: effects, concentration: false)
        return payload.entries.enumerated().compactMap { index, entry -> SpellHitEffectLinks? in
            guard
                let resolved = resolve(entry, fromPlugin: payload.sourcePlugin),
                let effect = resolved.effect.data
            else { return nil }
            let dual = payload.isDualCast ? resolved.dualCastArt : nil
            let shows = !effect.flags.contains(.noHitEffect)
            var links = SpellHitEffectLinks(
                plugin: resolved.sourcePlugin,
                imageSpaceModifier: effect.imageSpaceModifier,
                hitShader: shows ? dual?.effectShader ?? effect.hitShader : nil,
                hitEffectArt: shows ? dual?.hitEffectArt ?? effect.hitEffectArt : nil,
                explosion: effect.explosion,
                area: entry.area,
                duration: entry.duration
            )
            links.isAbsorb = effect.archetype == .absorb
            links.isMain = index == main
            links.hitSound = resolved.effect.sounds.first { $0.kind == Self.onHitSoundKind }
                .flatMap(\.descriptor)
                .flatMap { resolvedID($0, fromPlugin: resolved.sourcePlugin) }
                .flatMap(loadOrderFormID)
            return links
        }
    }
}
