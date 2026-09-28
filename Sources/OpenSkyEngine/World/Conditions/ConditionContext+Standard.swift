// The whole-game condition setup: a context with every feature's seam, and the
// registry with every feature's functions. It lives above the features because
// it names all of them; the condition core names none.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyWorldState

nonisolated extension ConditionContext {
    public init(
        globals: GlobalResolution = .empty,
        quests: QuestResolution = .empty,
        aliases: QuestAliasResolution = .empty,
        actors: ActorStateResolution = .empty,
        detection: DetectionResolution = .empty,
        dialogue: DialogueResolution = .empty,
        data: ConditionDataResolution = .empty,
        magic: MagicConditionResolution = .empty,
        perks: PerkConditionResolution = .empty,
        crime: CrimeConditionResolution = .empty,
        factions: FactionConditionResolution = .empty,
        referenceEnable: ReferenceEnableResolution = .empty,
        aliasQuest: FormID? = nil,
        clock: GameClock? = nil,
        references: RuntimeReferenceIndex = .empty,
        subject: ReferenceKey? = nil,
        target: ReferenceKey? = nil,
        random: ConditionRandom = ConditionRandom()
    ) {
        self.init()
        self.globals = globals
        self.quests = quests
        self.aliases = aliases
        self.actors = actors
        self.detection = detection
        self.dialogue = dialogue
        self.data = data
        self.magic = magic
        self.perks = perks
        self.crime = crime
        self.factions = factions
        self.referenceEnable = referenceEnable
        self.aliasQuest = aliasQuest
        self.clock = clock
        self.references = references
        self.subject = subject
        self.target = target
        self.random = random
    }
}

nonisolated extension ConditionFunctionRegistry {
    /// Every condition function OpenSky implements: the core families plus
    /// each feature's.
    public static let standard: ConditionFunctionRegistry = {
        var registry = ConditionFunctionRegistry()
        ConditionFunctions.installCore(into: &registry)
        ConditionFunctions.installQuest(&registry)
        ConditionFunctions.installActor(&registry)
        ConditionFunctions.installDetection(&registry)
        ConditionFunctions.installDialogue(&registry)
        ConditionFunctions.installData(&registry)
        ConditionFunctions.installMagic(&registry)
        ConditionFunctions.installPerk(&registry)
        ConditionFunctions.installCrime(&registry)
        ConditionFunctions.installFaction(&registry)
        return registry
    }()
}

nonisolated extension ConditionEvaluator {
    /// An evaluator over the whole-game registry.
    public init(context: ConditionContext, tally: ConditionTally = ConditionTally()) {
        self.init(context: context, registry: .standard, tally: tally)
    }
}

nonisolated extension ConditionTally {
    /// Unknown function indices ranked by count, named from the whole-game
    /// registry.
    public func rankedUnknownFunctions() -> [(name: String, count: Int)] {
        rankedUnknownFunctions(in: .standard)
    }
}
