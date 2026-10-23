// Weapon blood: a weapon model holds blood shapes whose effect shader sets the
// Weapon_Blood flag. They stay hidden until the weapon hits a bleeding actor, then
// draw blended at the blood's strength (docs/rendering/visual-effects.md).

import Metal

extension Renderer {
    /// Replaces the bloody weapons and the strength of their blood, 0 to 1.
    public func setBloodyWeapons(_ strengths: [MembraneTarget: Float]) {
        effects.bloodyWeapons = strengths.filter { $0.value > 0 }
    }

    /// The blood of each bloody weapon in the world view. The first-person weapon
    /// draws its blood in the arms pass.
    func encodeWeaponBlood(state: inout ScenePassState) {
        guard !isRenderDebugActive else { return }
        for (target, strength) in effects.bloodyWeapons.sorted(by: { "\($0.key)" < "\($1.key)" }) {
            let groups: [DrawGroup] = switch target {
            case .playerWeapon:
                isPlayerBodyVisible ? frameInput.rigs.body?.render.alphaTested ?? [] : []
            case .actorWeapon:
                membraneGroups(for: target)
            case .player, .actor:
                []
            }
            encodeWeaponBlood(groups: groups, strength: strength, state: &state)
        }
    }

    /// The blood shapes among `groups`, blended and depth read-only.
    func encodeWeaponBlood(groups: [DrawGroup], strength: Float, state: inout ScenePassState) {
        let blood = groups.filter(\.isWeaponBlood)
        guard !blood.isEmpty else { return }
        state.materialDepth = .readOnly
        state.weaponBloodAlpha = strength
        state.encoder.setDepthStencilState(waterDepthState)
        encode(
            groups: blood,
            staticPipeline: blendedPipeline,
            skinnedPipeline: skinnedBlendedPipelines.skinned,
            morphedSkinnedPipeline: skinnedBlendedPipelines.morphed,
            state: &state
        )
        endMaterialDrawState(state: &state)
        state.weaponBloodAlpha = nil
    }
}
