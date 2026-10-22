// What the magic coordinator asks the app to do. See docs/engine/coordinators.md.

import OpenSkyFormatsESM
import OpenSkyMagicInterface

/// One change to the world outside the magic domain, raised by a magic effect.
nonisolated public enum MagicCommand: Equatable, Sendable {
    /// A Stagger effect began on the actor, with its magnitude.
    case stagger(ReferenceKey, magnitude: Float)
    /// A Spawn Hazard effect began: the hazard is placed at the actor.
    case spawnHazard(ReferenceKey, at: ReferenceKey)
    /// Raise this event on the player's behaviour graph.
    case playerGraphEvent(String)
    /// A rune went off: set off its `PROJ`'s explosion at the point.
    case detonateRune(SpellPayload, at: SIMD3<Float>)
    /// Start or stop a casting hand's sound, a load-order `SNDR`, at the caster.
    case castingSound(FormID, caster: ReferenceKey, starts: Bool)
    /// Show or hide a casting hand's `ARTO`, written in `plugin`, on the caster.
    case castingArt(FormID, plugin: String, caster: ReferenceKey, starts: Bool)
    /// Show this line on the HUD, such as a refused cast's.
    case notice(String)
}
