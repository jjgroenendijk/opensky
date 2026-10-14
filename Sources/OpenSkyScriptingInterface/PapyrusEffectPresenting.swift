// The port the `VisualEffect`, `EffectShader`, and `ImageSpaceModifier` natives draw
// through. The app's effects adapter conforms. See docs/rendering/visual-effects.md.

import Foundation
import OpenSkyFormatsESM

@MainActor
public protocol PapyrusEffectPresenting: AnyObject {
    /// Attaches an `RFCT` or `EFSH` to `target`; a nil duration lasts until stopped.
    /// False when the form draws nothing.
    @discardableResult
    func playEffect(_ effect: ReferenceKey, on target: ReferenceKey, duration: Float?) -> Bool

    /// Removes the effect from `target`. False when none was playing.
    @discardableResult
    func stopEffect(_ effect: ReferenceKey, on target: ReferenceKey) -> Bool

    /// Starts an `IMAD`. A held one stays until removed. False when the form is no `IMAD`.
    @discardableResult
    func applyImageSpaceModifier(_ modifier: ReferenceKey, strength: Float, held: Bool) -> Bool

    func removeImageSpaceModifier(_ modifier: ReferenceKey)
}
