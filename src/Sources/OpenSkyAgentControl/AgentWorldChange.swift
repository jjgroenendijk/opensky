// The debug commands that change the world the way a script or a console line would:
// image space modifiers, spells, enable state, deletion, locks, activation, hit decals,
// and placed objects. Each takes the load-order FormID the reference game's console takes.

/// Starts or removes an image space modifier, as the `ImageSpaceModifier` natives do.
nonisolated public struct AgentModifierRequest: Equatable, Sendable {
    public let modifier: String
    public let strength: Float
    /// Seconds the modifier fades in, or out with `remove`.
    public let fadeSeconds: Float
    /// Held at full strength until removed, as `ApplyCrossFade` does.
    public let crossFade: Bool
    public let remove: Bool

    public init(
        modifier: String, strength: Float, fadeSeconds: Float, crossFade: Bool, remove: Bool
    ) {
        self.modifier = modifier
        self.strength = strength
        self.fadeSeconds = fadeSeconds
        self.crossFade = crossFade
        self.remove = remove
    }
}

nonisolated public enum AgentWorldChange: Equatable, Sendable {
    case imageSpaceModifier(AgentModifierRequest)
    /// Casts a spell from a caster at a target, as `Spell.Cast` does.
    case cast(spell: String, caster: String, target: String?)
    /// Adds or removes a spell, as `Actor.AddSpell` and `RemoveSpell` do.
    case spell(spell: String, reference: String, known: Bool)
    /// Enables or disables a reference, as `ObjectReference.Enable` and `Disable` do.
    case enable(reference: String, enabled: Bool)
    /// Deletes a reference, as `ObjectReference.Delete` does.
    case delete(reference: String)
    /// Locks or unlocks a reference, as `ObjectReference.Lock` does.
    case lock(reference: String, locked: Bool)
    /// Lets a looping sound finish its pass and end, as a `SoundRelease` event does.
    case release(sound: Int)
    /// Activates a reference, as `ObjectReference.Activate` does.
    case activate(reference: String, activator: String)
    /// Places a blood hit decal on an actor, `height` units above its feet.
    case decal(reference: String, height: Float)
    /// Places a new reference of a base object at another reference, as `PlaceAtMe` does.
    case spawn(base: String, anchor: String)

    static func parse(_ name: String, _ args: AgentArguments) throws(AgentFailure) -> Self? {
        switch name {
        case "imod": try parseModifier(args)
        case "cast":
            try .cast(
                spell: args.string("spell"), caster: args.optionalString("ref") ?? "player",
                target: args.optionalString("target")
            )
        case "spell":
            try .spell(
                spell: args.string("spell"), reference: args.optionalString("ref") ?? "player",
                known: args.bool("on", default: true)
            )
        case "enable", "disable":
            try .enable(reference: args.string("ref"), enabled: name == "enable")
        case "delete": try .delete(reference: args.string("ref"))
        case "lock":
            try .lock(reference: args.string("ref"), locked: args.bool("on", default: true))
        case "release": try .release(sound: args.int("id"))
        case "activate":
            try .activate(
                reference: args.string("ref"), activator: args.optionalString("by") ?? "player"
            )
        case "decal": try parseDecal(args)
        case "spawn":
            try .spawn(base: args.string("base"), anchor: args.optionalString("at") ?? "player")
        default: nil
        }
    }

    private static func parseModifier(_ args: AgentArguments) throws(AgentFailure) -> Self {
        let strength = try args.optionalFloat("strength") ?? 1
        guard strength.isFinite, strength >= 0 else { throw args.invalid("strength", "0 or more") }
        let fade = try args.optionalFloat("fade") ?? 0
        guard fade.isFinite, fade >= 0 else { throw args.invalid("fade", "0 or more seconds") }
        return try .imageSpaceModifier(AgentModifierRequest(
            modifier: args.string("modifier"), strength: strength, fadeSeconds: fade,
            crossFade: args.bool("crossfade", default: false),
            remove: args.bool("off", default: false)
        ))
    }

    private static func parseDecal(_ args: AgentArguments) throws(AgentFailure) -> Self {
        let height = try args.optionalFloat("height") ?? 100
        guard height.isFinite, height >= 0 else { throw args.invalid("height", "0 or more") }
        return try .decal(reference: args.string("ref"), height: height)
    }
}
