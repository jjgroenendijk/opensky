public import OpenSkyFormatsESM

/// One change to the world outside the magic domain, raised by a magic effect.
nonisolated public enum MagicCommand: Equatable, Sendable {
    /// A Stagger effect began on the actor, with its magnitude.
    case stagger(ReferenceKey, magnitude: Float)
    /// A spell of `caster` met the ward of the actor: Papyrus `OnWardHit`.
    case wardHit(SpellWardHit, caster: ReferenceKey, spell: ReferenceKey)
    /// The player's Telekinesis took hold of a body, or let it go: `OnGrab` and `OnRelease`.
    case playerGrab(ReferenceKey, held: Bool)
    /// A Spawn Hazard effect began: the hazard is placed at the actor.
    case spawnHazard(ReferenceKey, at: ReferenceKey)
    /// Raise this event on the player's behaviour graph.
    case playerGraphEvent(String)
    /// Raise this event on an NPC's behaviour graph.
    case actorGraphEvent(String, actor: ReferenceKey)
    /// Write this boolean variable of an NPC's behaviour graph, such as `bWantCastRight`.
    case actorGraphFlag(String, value: Bool, actor: ReferenceKey)
    /// A rune went off: set off its `PROJ`'s explosion at the point.
    case detonateRune(SpellPayload, at: SIMD3<Float>)
    /// Start or stop a casting hand's sound, a load-order `SNDR`, at the caster.
    case castingSound(FormID, caster: ReferenceKey, starts: Bool)
    /// Play an item's use sound, a load-order `SNDR`, at the actor who used it.
    case itemUseSound(FormID, actor: ReferenceKey)
    /// Show or hide a casting hand's `ARTO`, written in `plugin`, on the hand's magic node.
    case castingArt(FormID, plugin: String, caster: ReferenceKey, hand: SpellHand, starts: Bool)
    /// Show or drop the `MGEF` casting `LIGH`, written in `plugin`, at the caster's hand.
    case castingLight(FormID, plugin: String, caster: ReferenceKey, hand: SpellHand, starts: Bool)
    /// Show this line on the HUD, such as a refused cast's.
    case notice(String)
    /// The player's shout of `words` words went off: a witness may comment on it, and
    /// the controller rumbles.
    case playerShouted(words: Int)
    /// Show or hide an `EFSH`, written in `plugin`, on the actor, as Detect Life paints.
    case paintActor(ReferenceKey, shader: FormID, plugin: String, shown: Bool)
    /// A spell reached someone: its hit shaders, art, sounds, and image-space modifier.
    case spellHit(SpellHitEvent)
    /// Show or hide a weapon enchantment's shader and art on the actor's held weapon.
    case weaponEnchantVisual(WeaponEnchantVisual, actor: ReferenceKey, shown: Bool)
}

/// The look of a readied enchanted weapon: its main effect's enchant shader and art, or
/// the `RFCT` that replaces both. Every link is written in `plugin`.
nonisolated public struct WeaponEnchantVisual: Equatable, Hashable, Sendable {
    public let plugin: String
    public let shader: FormID?
    public let art: FormID?
    public let visuals: FormID?

    public init(plugin: String, shader: FormID?, art: FormID?, visuals: FormID? = nil) {
        self.plugin = plugin
        self.shader = shader
        self.art = art
        self.visuals = visuals
    }
}
