// The whole-game condition setup: a context with every feature's seam, and the
// registry with every feature's functions. It lives above the features because
// it names all of them; the condition core names none.

public import OpenSkyActorsInterface
public import OpenSkyConditions
public import OpenSkyCrimeInterface
public import OpenSkyDialogueInterface
public import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
public import OpenSkyPerceptionInterface
public import OpenSkyProgressionInterface
public import OpenSkyQuestsInterface
import OpenSkyScriptingInterface
import OpenSkyWorldConditionFunctions
public import OpenSkyWorldState

nonisolated extension ConditionContext {
    public init(
        functions: ConditionFunctionRegistry = .standard,
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
        self.init(functions: functions)
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
        ConditionFunctionsQuest.installQuest(&registry)
        ConditionFunctionsActor.installActor(&registry)
        ConditionFunctionsDetection.installDetection(&registry)
        ConditionFunctionsDialogue.installDialogue(&registry)
        ConditionFunctionsScene.installScene(&registry)
        ConditionFunctionsData.installData(&registry)
        ConditionFunctionsMagic.installMagic(&registry)
        ConditionFunctionsPerk.installPerk(&registry)
        ConditionFunctionsSkillUsage.installSkillUsage(&registry)
        ConditionFunctionsCrime.installCrime(&registry)
        ConditionFunctionsFaction.installFaction(&registry)
        ConditionFunctionsInventory.installInventory(&registry)
        ConditionFunctionsLock.installLock(&registry)
        ConditionFunctionsAttack.installAttack(&registry)
        ConditionFunctionsReferenceState.installReferenceState(&registry)
        ConditionFunctionsCamera.installCamera(&registry)
        ConditionFunctionsFurniture.installFurniture(&registry)
        ConditionFunctionsScriptState.installScriptState(&registry)
        ConditionFunctionsPackage.installPackage(&registry)
        ConditionFunctionsMotion.installMotion(&registry)
        ConditionFunctionsPlace.installWorldPlaces(&registry)
        ConditionFunctionsMount.installMounts(&registry)
        return registry
    }()
}

nonisolated extension ConditionTally {
    /// Unknown function indices ranked by count, named from the whole-game
    /// registry.
    func rankedUnknownFunctions() -> [(name: String, count: Int)] {
        rankedUnknownFunctions(in: .standard)
    }
}
