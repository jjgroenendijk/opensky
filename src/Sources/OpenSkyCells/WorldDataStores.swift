// The session stores the main actor reads. The build queue never touches them.

import OpenSkyActorPresentation
public import OpenSkyAIPackages
public import OpenSkyAudio
public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
public import OpenSkyPlayer
public import OpenSkyWeather
public import OpenSkyWorldInterface
public import OpenSkyWorldState

/// The data half of a streaming session, split from `BuilderCellSceneProvider`
/// so the runner can own the builder alone (docs/engine/cell-streaming.md).
nonisolated public struct WorldDataStores {
    /// Compiled-script source for the Papyrus world runtime; nil on synthetic scenes.
    public var scriptFileSystem: (any GameFileSource)?
    /// The same master-list resolver every streamed reference key came from.
    public var scriptFormIDResolver: FormIDResolver
    /// Every placed record by key, for references whose cell is not loaded.
    public var placedRecords: PlacedRecordLookup?
    /// Weather runtime for this worldspace; nil when the plugin has no WTHR.
    public var weatherSystem: WeatherSystem?
    /// Sound record index (SOUN/SNDR); nil when the plugin has no sound data.
    public var soundStore: SoundRecordStore?
    /// Footstep index (FSTS/FSTP/IPDS/IPCT); nil when the session was built
    /// without one, which is every synthetic scene.
    public var footstepStore: FootstepStore?
    /// MATT index; nil on a synthetic scene, and then the footstep
    /// readout names a material by FormID.
    public var materialTypes: MaterialTypeIndex?
    /// Acoustic-space index (ASPC); nil when the plugin has no ASPC records.
    public var aspcStore: AcousticSpaceStore?
    /// Music record index (MUSC/MUST); nil when the plugin has no music data.
    public var musicStore: MusicRecordStore?
    /// Global-variable index (GLOB); nil when the plugin has no GLOB records.
    public var globalStore: GlobalStore?
    /// Quest index (QUST); nil when the plugin has no QUST records, and then
    /// every `Quest` native reports itself unavailable rather than guessing.
    public var questStore: QuestStore?
    /// LCTN/LCRT lookup for quest aliases and CELL location names.
    public var locationStore: LocationStore?
    /// Topic, response and voice-type records for the dialogue runtime.
    public var dialogueStore: DialogueStore?
    /// PACK records plus resolved NPC_ package lists.
    public var packageStore: PackageStore?
    /// Item/container/leveled-list indexes; nil when the session
    /// was built without them, which is every synthetic scene.
    public var inventoryBaselines: InventoryBaselineResolver?
    public var storyData = StoryData()
    /// Load-order idle records; nil on a synthetic scene, and then no actor idles.
    public var idleStore: IdleStore?
    /// Load-order effect records; nil on a synthetic scene, and then no effect plays.
    public var effectRecords: EffectRecordStore?
    /// Load-order CAMS, CPTH, CSTY, MESG, and LSCR; nil on a synthetic scene.
    public var presentationRecords: PresentationRecordStore?
    /// The `fDiffMult*` GMSTs; the documented defaults on a synthetic scene.
    public var difficultySettings = DifficultySettings.synthetic
    /// The bribe and intimidation settings; OpenSky's fallbacks on a synthetic scene.
    public var speechCheckSettings = SpeechCheckSettings.fallback
    /// Every GMST of the load order, which each subsystem resolves its settings from
    /// when it is wired. Empty on a synthetic scene, so every subsystem reads vanilla.
    public var gameSettings = GameSettingStore(plugins: [])
    /// The player record, races, and map markers; nil on a synthetic scene.
    public var menuRecords: MenuRecordData?
    /// RACE/CLAS/NPC_ stat indexes; nil on the same synthetic
    /// scenes, and then actor values report themselves unavailable.
    public var actorValueBaselines: ActorValueBaselineResolver?
    /// Load-order MGEF index; nil on the same synthetic scenes,
    /// and then active effects report themselves unavailable.
    public var magicEffectStore: MagicEffectStore?
    /// Plugin every magic item's EFID links are relative to.
    public var magicItemPluginName: String?
    /// Load-order SHOU index, which an AI Shout procedure casts from.
    public var shoutStore: ShoutStore?
    /// Load-order FACT index; nil on the same synthetic scenes,
    /// and then every actor derives as neutral toward everyone.
    public var factionStore: FactionStore?
    /// Load-order FLST index; nil on the same synthetic scenes,
    /// and then vendors trade without their keyword lists.
    public var formListStore: FormListStore?
    /// GMST-derived walk/run values plus explicit documented fallbacks.
    public var movementConfiguration: PlayerMovementConfiguration = .synthetic
    /// Every `MOVT` record, which an actor's graph state picks its speeds from.
    public var movementTypes: MovementTypeStore = .empty
    /// A ridden horse's gaits, from its movement types.
    public var mountMovementConfiguration: PlayerMovementConfiguration = .synthetic
    /// A dragon's flight, from the dragon movement types.
    public var dragonFlightSettings: DragonFlightSettings = .standard
    /// GMST-derived combat distance and block factors,
    /// defaulting to the documented vanilla numbers on a synthetic scene.
    public var combatSettings: CombatSettings = .synthetic
    /// GMST-derived arrow tilt-up angles and visible-move distance, defaulting to the
    /// UESP-documented numbers on a synthetic scene.
    public var archerySettings: ArcherySettings = .synthetic

    /// The spell, perk, and skill records the progression and magic runtimes start from.
    public var progression = WorldProgressionStores()
    /// The trade, lock, reset, relationship, and detection records.
    public var rules = WorldRuleStores()

    public init(
        scriptFormIDResolver: FormIDResolver,
        scriptFileSystem: (any GameFileSource)? = nil,
        weatherSystem: WeatherSystem? = nil,
        soundStore: SoundRecordStore? = nil,
        footstepStore: FootstepStore? = nil,
        materialTypes: MaterialTypeIndex? = nil,
        aspcStore: AcousticSpaceStore? = nil,
        musicStore: MusicRecordStore? = nil,
        globalStore: GlobalStore? = nil,
        questStore: QuestStore? = nil,
        locationStore: LocationStore? = nil,
        dialogueStore: DialogueStore? = nil,
        packageStore: PackageStore? = nil,
        inventoryBaselines: InventoryBaselineResolver? = nil,
        actorValueBaselines: ActorValueBaselineResolver? = nil,
        magicEffectStore: MagicEffectStore? = nil,
        magicItemPluginName: String? = nil,
        factionStore: FactionStore? = nil,
        formListStore: FormListStore? = nil,
        movementConfiguration: PlayerMovementConfiguration = .synthetic,
        combatSettings: CombatSettings = .synthetic,
        archerySettings: ArcherySettings = .synthetic
    ) {
        self.scriptFileSystem = scriptFileSystem
        self.scriptFormIDResolver = scriptFormIDResolver
        self.weatherSystem = weatherSystem
        self.soundStore = soundStore
        self.footstepStore = footstepStore
        self.materialTypes = materialTypes
        self.aspcStore = aspcStore
        self.musicStore = musicStore
        self.globalStore = globalStore
        self.questStore = questStore
        self.locationStore = locationStore
        self.dialogueStore = dialogueStore
        self.packageStore = packageStore
        self.inventoryBaselines = inventoryBaselines
        self.actorValueBaselines = actorValueBaselines
        self.magicEffectStore = magicEffectStore
        self.magicItemPluginName = magicItemPluginName
        self.factionStore = factionStore
        self.formListStore = formListStore
        self.movementConfiguration = movementConfiguration
        self.combatSettings = combatSettings
        self.archerySettings = archerySettings
    }
}
