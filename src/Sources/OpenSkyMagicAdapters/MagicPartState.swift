// What the Magic adapter parts remember between calls. The owner keeps one and hands it to
// each part that needs it, so no part holds the owner.

public import OpenSkyFormatsESM

public final class MagicPartState {
    /// The NPCs a Grab Actor effect holds through the ridden-actor hold.
    public var grabbedActors: Set<ReferenceKey> = []
    /// The `MGEF` casting light each readying caster shows, by caster.
    public var castingLights: [ReferenceKey: ReferenceKey] = [:]
    /// Race and base keywords never change in a session, and a lookup decodes the record.
    public var actorKeywordAnswers: [ActorKeywordQuery: Bool] = [:]

    public init() {}
}
