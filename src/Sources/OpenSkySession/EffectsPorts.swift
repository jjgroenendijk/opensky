public import OpenSkyEffects
public import OpenSkyFormatsESM
public import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkySessionInterface

extension EffectsCoordinator: EffectsPort {
    @discardableResult public func attach(
        _ key: ReferenceKey,
        to anchor: EffectAnchor,
        cause: VisualEffectCause,
        placement: (duration: Float?, facing: ReferenceKey?)
    ) -> Int? {
        attach(
            key, to: anchor, cause: cause, duration: placement.duration,
            facing: placement.facing
        )
    }

    @discardableResult public func startModifier(
        _ key: ReferenceKey,
        strength: Float,
        fade: (looping: Bool, fadeIn: Float),
        on imageSpace: inout ImageSpaceState
    ) -> Bool {
        startModifier(
            key, strength: strength, looping: fade.looping, fadeIn: fade.fadeIn,
            on: &imageSpace
        )
    }
}

extension PlayerHealthCues: PlayerHealthCuesPort {}
