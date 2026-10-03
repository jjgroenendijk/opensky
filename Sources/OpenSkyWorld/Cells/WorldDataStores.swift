// The session stores the main actor reads. The build queue never touches them.

import OpenSkyAudio
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyWorldState

/// The data half of a streaming session, split from `BuilderCellSceneProvider`
/// so the runner can own the builder alone (docs/engine/cell-streaming.md).
nonisolated public struct WorldDataStores: WorldDataProviding, WeatherProviding,
    AudioDataProviding, MovementConfigurationProviding, GlobalDataProviding,
    ScriptDataProviding, ItemDataProviding, BarterDataProviding, QuestDataProviding,
    LocationDataProviding, DialogueDataProviding, ActorValueDataProviding, CombatDataProviding,
    PackageDataProviding, MagicDataProviding, ProgressionDataProviding,
    FactionDataProviding, LockTrapDataProviding, StoryDataProviding
{
    /// Compiled-script source for the Papyrus world runtime; nil on synthetic scenes.
    public var scriptFileSystem: (any GameFileSource)?
    /// The same master-list resolver every streamed reference key came from.
    public var scriptFormIDResolver: FormIDResolver
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
    /// Equippable-item slot index; nil on the same synthetic
    /// scenes, and then equipping reports itself unavailable.
    public var equipmentCatalog: EquipmentCatalog?
    /// Load-order recipes and the item plugin's stations; nil on a synthetic scene.
    public var craftingCatalog: CraftingCatalog?
    /// Lockpicking tuning, the lockpick item, and hazards; defaults on a synthetic scene.
    public var lockTrapData = LockTrapData()
    public var storyData = StoryData()
    /// RACE/CLAS/NPC_ stat indexes; nil on the same synthetic
    /// scenes, and then actor values report themselves unavailable.
    public var actorValueBaselines: ActorValueBaselineResolver?
    /// Load-order MGEF index; nil on the same synthetic scenes,
    /// and then active effects report themselves unavailable.
    public var magicEffectStore: MagicEffectStore?
    /// Plugin every magic item's EFID links are relative to.
    public var magicItemPluginName: String?
    /// Load-order SPEL and SCRL index; nil on the same synthetic
    /// scenes, and then the spellbook reports itself unavailable.
    public var spellStore: SpellStore?
    /// Load-order EQUP index, which answers which hands a readied
    /// spell takes.
    public var equipSlotStore: EquipSlotStore?
    /// Load-order ENCH index; nil on the same synthetic scenes, and
    /// then an enchanted item applies nothing and the readout says so.
    public var enchantmentStore: EnchantmentStore?
    /// Load-order PERK index; nil on the same synthetic scenes,
    /// and then the perk runtime reports itself unavailable.
    public var perkStore: PerkStore?
    /// Load-order FACT index; nil on the same synthetic scenes,
    /// and then every actor derives as neutral toward everyone.
    public var factionStore: FactionStore?
    /// Load-order RELA and ASTP index; nil on the same synthetic
    /// scenes, and then no pair overrides its factions.
    public var relationshipStore: RelationshipStore?
    /// Load-order FLST index; nil on the same synthetic scenes,
    /// and then vendors trade without their keyword lists.
    public var formListStore: FormListStore?
    /// Load-order AVIF index; nil on the same synthetic scenes,
    /// and then skill advancement has no parameters and reports the drop.
    public var actorValueInformation: ActorValueInformationStore?
    /// GMST-derived skill-use curve and per-rank character experience, defaulting to
    /// the documented numbers on a synthetic scene.
    public var skillAdvancementSettings: SkillAdvancementSettings = .documentedDefaults
    /// GMST-derived level curve and level-up rewards, defaulting
    /// to the documented numbers on a synthetic scene.
    public var characterLevelSettings: CharacterLevelSettings = .documentedDefaults
    /// GMST-derived walk/run values plus explicit documented fallbacks.
    public var movementConfiguration: PlayerMovementConfiguration = .synthetic
    /// GMST-derived `fBarterMin` and `fBarterMax` at the milestone's fixed
    /// Speech value, defaulting to the documented vanilla numbers.
    public var barterPricing: BarterPricing = .vanilla
    /// GMST-derived combat distance and block factors,
    /// defaulting to the documented vanilla numbers on a synthetic scene.
    public var combatSettings: CombatSettings = .synthetic
    /// GMST-derived arrow tilt-up angles and visible-move distance, defaulting to the
    /// UESP-documented numbers on a synthetic scene.
    public var archerySettings: ArcherySettings = .synthetic
    /// GMST-derived detection ranges, noise weights, and thresholds, defaulting to
    /// the documented numbers on a synthetic scene.
    public var detectionSettings: DetectionSettings = .synthetic

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
        equipmentCatalog: EquipmentCatalog? = nil,
        actorValueBaselines: ActorValueBaselineResolver? = nil,
        magicEffectStore: MagicEffectStore? = nil,
        magicItemPluginName: String? = nil,
        spellStore: SpellStore? = nil,
        equipSlotStore: EquipSlotStore? = nil,
        enchantmentStore: EnchantmentStore? = nil,
        perkStore: PerkStore? = nil,
        factionStore: FactionStore? = nil,
        relationshipStore: RelationshipStore? = nil,
        formListStore: FormListStore? = nil,
        actorValueInformation: ActorValueInformationStore? = nil,
        skillAdvancementSettings: SkillAdvancementSettings = .documentedDefaults,
        characterLevelSettings: CharacterLevelSettings = .documentedDefaults,
        movementConfiguration: PlayerMovementConfiguration = .synthetic,
        barterPricing: BarterPricing = .vanilla,
        combatSettings: CombatSettings = .synthetic,
        archerySettings: ArcherySettings = .synthetic,
        detectionSettings: DetectionSettings = .synthetic
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
        self.equipmentCatalog = equipmentCatalog
        self.actorValueBaselines = actorValueBaselines
        self.magicEffectStore = magicEffectStore
        self.magicItemPluginName = magicItemPluginName
        self.spellStore = spellStore
        self.equipSlotStore = equipSlotStore
        self.enchantmentStore = enchantmentStore
        self.perkStore = perkStore
        self.factionStore = factionStore
        self.relationshipStore = relationshipStore
        self.formListStore = formListStore
        self.actorValueInformation = actorValueInformation
        self.skillAdvancementSettings = skillAdvancementSettings
        self.characterLevelSettings = characterLevelSettings
        self.movementConfiguration = movementConfiguration
        self.barterPricing = barterPricing
        self.combatSettings = combatSettings
        self.archerySettings = archerySettings
        self.detectionSettings = detectionSettings
    }
}
