// The race, sex, voice type, and name of an actor base after template inheritance, as the
// Papyrus identity natives answer them. Pure: built over the record indexes.

import OpenSkyFormatsESM

nonisolated public struct ActorIdentityRecords: Sendable {
    public private(set) var templates: ActorTemplateResolver
    public let races: [UInt32: Race]

    /// This resolver for one placed reference's roll.
    public func rolling(_ roll: LeveledRoll?) -> Self {
        var copy = self
        copy.templates = templates.rolling(roll)
        return copy
    }

    public init(templates: ActorTemplateResolver, races: [UInt32: Race]) {
        self.templates = templates
        self.races = races
    }

    public init(resolver: ActorValueResolver) {
        self.init(templates: resolver.templates, races: resolver.races)
    }

    /// `useTraits` decides which record of the template chain gives the race. A
    /// placed actor passes its `roll`, which picks its leveled template.
    public func race(ofBase base: FormID, roll: LeveledRoll? = nil) -> FormID? {
        (try? templates.rolling(roll).resolve(base: base))?.race.value
    }

    public func isFemale(ofBase base: FormID, roll: LeveledRoll? = nil) -> Bool? {
        (try? templates.rolling(roll).resolve(base: base))?.isFemale.value
    }

    /// `VTCK` after `useTraits` inheritance.
    public func voiceType(ofBase base: FormID, roll: LeveledRoll? = nil) -> FormID? {
        (try? templates.rolling(roll).resolve(base: base))?.voiceType.value
    }

    /// The `FULL` of an actor base, after `useBaseData`, or of a race.
    public func name(of form: FormID) -> LString? {
        if templates.actors[form.rawValue] != nil {
            return (try? templates.resolveName(base: form))?.value
        }
        return races[form.rawValue]?.name
    }
}
