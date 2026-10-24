// Blood beyond the impact: the splatters on the screen when the player is hit, the
// blood a weapon keeps, and the default blood of a hit with no impact data
// (docs/rendering/visual-effects.md#blood).

import Metal
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import simd

extension EffectsCoordinator {
    /// The default blood decal's size range, in game units. OpenSky's numbers: the
    /// game names the texture but not a size.
    static let defaultBloodDecalSize: ClosedRange<Float> = 24 ... 48

    public func applyBloodSettings(_ settings: BloodEffectSettings) {
        bloodSettings = settings
        screenBlood.settings = settings
        weaponBlood.settings = settings
        screenBloodTextures = nil
    }

    public var screenBloodEnabled: Bool {
        get { screenBlood.enabled }
        set {
            screenBlood.enabled = newValue
            if !newValue {
                screenBlood.removeAll()
            }
        }
    }

    /// A hit of `damage` on the player. Returns how many splatters it placed.
    @discardableResult
    public func splatterScreen(damage: Float) -> Int {
        guard screenBlood.enabled else { return 0 }
        return screenBlood.splatter(damage: damage)
    }

    /// `count` splatters at once, for Papyrus `TriggerScreenBlood`.
    @discardableResult
    public func splatterScreen(count: Int) -> Int {
        guard screenBlood.enabled else { return 0 }
        return screenBlood.splatter(count: count)
    }

    /// Removes the blood on screen, for Papyrus `ClearTempEffects`.
    public func clearTemporaryBlood() {
        screenBlood.removeAll()
    }

    /// The weapon of `holder` hit a bleeding actor.
    public func bloodyWeapon(of holder: ReferenceKey) {
        let target: MembraneTarget? = holder == .player ? .playerWeapon
            : world?.membraneTarget(of: holder).flatMap { target in
                guard case let .actor(owner) = target else { return nil }
                return .actorWeapon(owner)
            }
        if let target {
            weaponBlood.bloody(target)
        }
    }

    /// A hit on `actor` that its impact data shows nothing for: the default blood
    /// model, and the default blood decal on the ground under it.
    public func showDefaultBlood(on actor: ReferenceKey, at position: SIMD3<Float>, melee: Bool) {
        let model = melee && !bloodSettings.meleeParticleModel.isEmpty
            ? bloodSettings.meleeParticleModel : bloodSettings.particleModel
        if impactModelsEnabled, !model.isEmpty {
            showModel(model, at: position, cause: .impact)
        }
        guard
            let key = NIFShaderTextureSet.vfsKey(for: bloodSettings.decalTexture),
            let look = DecalLook(
                texture: key,
                decal: DecalData(
                    width: Self.defaultBloodDecalSize, height: Self.defaultBloodDecalSize
                )
            )
        else { return }
        let feet = world?.effectTransform(of: actor)?.columns.3
        let ground = SIMD3(position.x, position.y, feet?.z ?? position.z)
        if decals.place(look, at: ground, normal: SIMD3(0, 0, 1)) != nil {
            decalsChanged = true
        }
    }

    /// The cut of a dismemberment, when the race gives no effect of its own.
    public func showDismemberParticle(at position: SIMD3<Float>) {
        guard !bloodSettings.dismemberParticleModel.isEmpty else { return }
        showModel(bloodSettings.dismemberParticleModel, at: position, cause: .impact)
    }

    /// Ages the blood and hands the renderer the splatters.
    func stepBlood(_ seconds: Float, renderer: Renderer) {
        screenBlood.advance(seconds)
        weaponBlood.advance(seconds)
        let draws = screenBlood.draws
        guard !draws.isEmpty || drewScreenBlood else { return }
        renderer.setScreenBlood(draws, textures: draws.isEmpty ? nil : loadScreenBloodTextures())
        drewScreenBlood = !draws.isEmpty
    }

    private func loadScreenBloodTextures() -> ScreenBloodTextures? {
        if let screenBloodTextures {
            return screenBloodTextures
        }
        guard let textures = meshes?.textures else { return nil }
        func load(_ path: String) -> MTLTexture {
            textures.texture(key: NIFShaderTextureSet.vfsKey(for: path), usage: .color)
        }
        let loaded = ScreenBloodTextures(
            color: load(bloodSettings.splatterColorTexture),
            alpha: load(bloodSettings.splatterAlphaTexture),
            flare: load(bloodSettings.flareTexture)
        )
        screenBloodTextures = loaded
        return loaded
    }
}
