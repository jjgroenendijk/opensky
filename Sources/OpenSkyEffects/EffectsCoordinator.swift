// The shell of visual effects: turns spell hits and race abilities into
// attached effects, starts image-space modifiers, and hands the renderer this
// frame's effect models and membranes. The rules sit in `VisualEffectRuntime`
// and the record resolvers. See docs/rendering/visual-effects.md.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyRendering
import simd

/// What the effects need from the session around them.
@MainActor
public protocol EffectsWorld: AnyObject {
    /// An actor's feet, facing its heading; nil when it is not resident.
    func effectTransform(of actor: ReferenceKey) -> float4x4?
    /// The view, for effects that ride the camera; nil before a renderer exists.
    var effectCamera: VisualEffectRuntime.CameraPose? { get }
    /// The meshes a membrane on `actor` covers; nil when none are drawn.
    func membraneTarget(of actor: ReferenceKey) -> MembraneTarget?
    func detonateEffectExplosion(_ explosion: ReferenceKey, at position: SIMD3<Float>)
}

public final class EffectsCoordinator {
    /// Seconds a hit-effect art model stays when its spell is instant.
    public static let instantArtDuration: Float = 2

    public weak var world: (any EffectsWorld)?
    public private(set) var records = EffectRecordStore.empty
    public private(set) var catalog = EffectCatalog.empty
    public internal(set) var visualEffects = VisualEffectRuntime()
    public private(set) var spellHitCount = 0
    public private(set) var lastSpellHit = "No spell hit yet."
    /// Model paths that failed to load, so a bad path is tried once.
    public private(set) var failedModels: Set<String> = []
    /// Marks impacts leave on surfaces.
    public internal(set) var decals = DecalRuntime()
    /// Impact models (dust, sparks, blood spray) show where a hit or step lands.
    public var impactModelsEnabled = true
    public internal(set) var impactCount = 0
    /// The last impact shown, so the readout can show it again.
    public internal(set) var lastImpact: (impact: Impact, decal: ImpactDecal?)?
    var decalsChanged = false
    /// The particle systems of each live effect, by instance id.
    var effectParticles: [Int: EffectParticles] = [:]
    var meshes: MeshLibrary?
    private var drewModels = false
    /// Blood that lasts: on the screen after the player is hit, and on weapons.
    public internal(set) var screenBlood = ScreenBloodRuntime()
    public internal(set) var weaponBlood = WeaponBloodRuntime()
    public internal(set) var bloodSettings = BloodEffectSettings.vanilla
    var screenBloodTextures: ScreenBloodTextures?
    var drewScreenBlood = false

    public init() {}

    /// `meshes` is a library only the main thread uses; nil draws membranes only.
    public func wire(records: EffectRecordStore, meshes: MeshLibrary?) {
        self.records = records
        self.meshes = meshes
        catalog = EffectCatalog(records: records)
    }

    /// Attaches any `RFCT`, `EFSH`, or `ARTO` by key. Nil when it draws nothing.
    @discardableResult
    public func attach(
        _ key: ReferenceKey,
        to anchor: EffectAnchor,
        cause: VisualEffectCause,
        duration: Float?
    ) -> Int? {
        guard let spec = records.visualEffectSpec(key) else { return nil }
        return visualEffects.attach(spec, to: anchor, cause: cause, duration: duration)
    }

    /// Removes the `RFCT`, `EFSH`, or `ARTO` named by `key` from `anchor`. Returns how
    /// many instances went.
    @discardableResult
    public func detach(_ key: ReferenceKey, from anchor: EffectAnchor) -> Int {
        guard let spec = records.visualEffectSpec(key) else { return 0 }
        return visualEffects.detach(spec, from: anchor)
    }

    /// Casting art is "on the hands while preparing to cast". No anchor names a hand,
    /// so it rides the actor. Returns false when the art draws nothing.
    @discardableResult
    public func showCastingArt(
        _ art: FormID, fromPlugin plugin: String, on actor: ReferenceKey, shown: Bool
    ) -> Bool {
        guard let key = records.resolve(art, fromPlugin: plugin) else { return false }
        guard shown else { return detach(key, from: .actor(actor)) > 0 }
        return attach(key, to: .actor(actor), cause: .casting, duration: nil) != nil
    }

    public func removeAll(cause: VisualEffectCause? = nil) {
        visualEffects.removeAll(cause: cause)
    }

    public func detachAll(from actor: ReferenceKey) {
        visualEffects.detachAll(from: .actor(actor))
    }

    /// Shows a bare model, such as an explosion's `MODL`, at a point for a while.
    public func showModel(_ path: String, at position: SIMD3<Float>, cause: VisualEffectCause) {
        let spec = VisualEffectSpec(name: path, artModel: path, membrane: nil)
        visualEffects.attach(
            spec,
            to: .point(position),
            cause: cause,
            duration: Self.instantArtDuration
        )
    }

    /// Starts one `IMAD` on `imageSpace`. False when the key names none.
    @discardableResult
    public func startModifier(
        _ key: ReferenceKey,
        strength: Float,
        looping: Bool = false,
        on imageSpace: inout ImageSpaceState
    ) -> Bool {
        guard let adapter = records.imageSpaceAdapters.record(key) else { return false }
        imageSpace.modifiers.start(adapter.record, key: key, strength: strength, looping: looping)
        return true
    }

    /// Stops every running instance of the `IMAD` `key` on `imageSpace`.
    public func stopModifier(_ key: ReferenceKey, on imageSpace: inout ImageSpaceState) {
        imageSpace.modifiers.stop(key: key)
    }

    /// One landed spell: the modifier when the player was hit, the hit shader and art
    /// on each target, and the explosion of an area effect at the struck actor.
    public func handleSpellHit(_ event: SpellHitEvent, imageSpace: inout ImageSpaceState) {
        spellHitCount += 1
        let targets = event.hit.targets.map(\.key)
        var started = 0
        var attached = 0
        for link in event.links {
            if
                targets.contains(.player),
                let modifier = records.resolve(link.imageSpaceModifier, fromPlugin: link.plugin),
                startModifier(modifier, strength: 1, on: &imageSpace)
            {
                started += 1
            }
            attached += attachHitEffects(link, to: targets)
            detonateAreaExplosion(link, hit: event.hit)
        }
        lastSpellHit = "\(event.hit.payload.name): \(targets.count) target(s), "
            + "\(attached) effect(s), \(started) image-space modifier(s)"
    }

    /// The lasting look of an actor's race abilities: hit shaders and art that stay.
    public func attachLasting(_ links: [SpellHitEffectLinks], to actor: ReferenceKey) {
        for link in links {
            for effect in [link.hitShader, link.hitEffectArt] {
                guard let key = records.resolve(effect, fromPlugin: link.plugin) else { continue }
                attach(key, to: .actor(actor), cause: .race, duration: nil)
            }
        }
    }

    /// Ages the effects and hands the renderer this frame's models and membranes.
    /// `extraModels` are the debris and hazard models other runtimes own.
    public func step(
        _ seconds: Float,
        extraModels: [VisualEffectModel],
        renderer: Renderer
    ) throws {
        visualEffects.advance(seconds)
        stepBlood(seconds, renderer: renderer)
        let world = world
        let models = visualEffects.models(camera: world?.effectCamera) { anchor in
            switch anchor {
            case let .actor(key): world?.effectTransform(of: key)
            case let .point(position): Self.translation(position)
            case let .surface(position, normal): Self.surfaceTransform(position, normal: normal)
            }
        } + extraModels
        if !models.isEmpty || drewModels {
            try renderer.setEffectPlacements(models.compactMap(placement))
            drewModels = !models.isEmpty
        }
        try syncParticles(models, renderer: renderer)
        try syncDecals(renderer: renderer)
        try renderer.setMembranes(visualEffects.membranes { anchor in
            guard case let .actor(key) = anchor else { return nil }
            return world?.membraneTarget(of: key)
        })
        renderer.setBloodyWeapons(weaponBlood.strengths)
    }

    private func attachHitEffects(_ link: SpellHitEffectLinks, to targets: [ReferenceKey]) -> Int {
        var attached = 0
        for effect in [link.hitShader, link.hitEffectArt] {
            guard
                let key = records.resolve(effect, fromPlugin: link.plugin),
                let spec = records.visualEffectSpec(key)
            else { continue }
            let duration = link.duration > 0
                ? Float(link.duration)
                : spec.membrane?.hitDuration ?? Self.instantArtDuration
            for target in targets
                where visualEffects.attach(
                    spec,
                    to: .actor(target),
                    cause: .spellHit,
                    duration: duration
                )
                != nil
            {
                attached += 1
            }
        }
        return attached
    }

    private func detonateAreaExplosion(_ link: SpellHitEffectLinks, hit: SpellHit) {
        guard
            link.area > 0,
            let explosion = records.resolve(link.explosion, fromPlugin: link.plugin),
            let struck = hit.targets.first(where: \.isDirect) ?? hit.targets.first,
            let transform = world?.effectTransform(of: struck.key)
        else { return }
        let center = transform.columns.3
        world?.detonateEffectExplosion(explosion, at: SIMD3(center.x, center.y, center.z))
    }

    private func placement(_ model: VisualEffectModel) -> RenderPlacement? {
        guard let meshes, !failedModels.contains(model.path) else { return nil }
        do {
            return try RenderPlacement(
                model: meshes.model(path: model.path),
                transform: model.transform,
                castsShadows: false,
                layer: .particles
            )
        } catch {
            failedModels.insert(model.path)
            return nil
        }
    }

    static func translation(_ position: SIMD3<Float>) -> float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4(position, 1)
        return matrix
    }
}
