// The race, sex, voice type, and name of an actor base after template inheritance, as the
// Papyrus identity natives answer them. Pure: built over the record indexes.

import OpenSkyFormatsESM

nonisolated public struct ActorIdentityRecords: Sendable {
    public let templates: ActorTemplateResolver
    public let races: [UInt32: Race]

    public init(templates: ActorTemplateResolver, races: [UInt32: Race]) {
        self.templates = templates
        self.races = races
    }

    public init(resolver: ActorValueResolver) {
        self.init(templates: resolver.templates, races: resolver.races)
    }

    /// `useTraits` decides which record of the template chain gives the race.
    public func race(ofBase base: FormID) -> FormID? {
        (try? templates.resolve(base: base))?.race.value
    }

    public func isFemale(ofBase base: FormID) -> Bool? {
        (try? templates.resolve(base: base))?.isFemale.value
    }

    /// `VTCK` after `useTraits` inheritance.
    public func voiceType(ofBase base: FormID) -> FormID? {
        (try? templates.resolve(base: base))?.voiceType.value
    }

    /// The `FULL` of an actor base, after `useBaseData`, or of a race.
    public func name(of form: FormID) -> LString? {
        if templates.actors[form.rawValue] != nil {
            return (try? templates.resolveName(base: form))?.value
        }
        return races[form.rawValue]?.name
    }
}
