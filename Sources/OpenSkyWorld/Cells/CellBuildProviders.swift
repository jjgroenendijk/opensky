// Optional capability seams a `CellSceneProvider` can adopt: what a real-data provider
// can hand the main thread that a synthetic scene cannot. Every value is immutable after
// `init`, so main-thread reads are safe while the builder stays on its queue.

import Foundation
import OpenSkyAudio
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyWorldState

/// Optional weather runtime for the renderer, built once from the same ESM data.
nonisolated public protocol WeatherProviding {
    var weatherSystem: WeatherSystem? { get }
}

/// Optional GLOB index. With the session's `WorldStateStore` it builds the
/// `GlobalResolution` that conditions, the clock and weather read.
nonisolated public protocol GlobalDataProviding {
    var globalStore: GlobalStore? { get }
}

/// Optional QUST index. With the session's `WorldStateStore` it builds the `QuestRuntime`
/// that the `Quest` natives mutate and quest scripts start from.
nonisolated public protocol QuestDataProviding {
    var questStore: QuestStore? { get }
}

/// Optional load-order-wide LCTN index used while filling direct location
/// aliases and resolving CELL XLCN links.
nonisolated public protocol LocationDataProviding {
    var locationStore: LocationStore? { get }
}

/// Optional DIAL/INFO/VTYP index for the dialogue runtime; nil on synthetic scenes.
nonisolated public protocol DialogueDataProviding {
    var dialogueStore: DialogueStore? { get }
}

/// Optional PACK/NPC_ schedule index for the AI panel; nil on synthetic scenes.
nonisolated public protocol PackageDataProviding {
    var packageStore: PackageStore? { get }
}

/// Load-order IDLE, IDLM, ANIO, and AACT records for the idle runtime.
nonisolated public protocol IdleDataProviding {
    var idleStore: IdleStore? { get }
}

/// Load-order cameras, combat styles, messages, and loading screens.
/// The player record, playable races, map markers, and map settings the menus read.
nonisolated public protocol MenuDataProviding {
    var menuRecords: MenuRecordData? { get }
}

nonisolated public protocol PresentationDataProviding {
    var presentationRecords: PresentationRecordStore? { get }
}

/// Load-order effect records: image spaces, effect shaders, explosions, output models.
nonisolated public protocol EffectDataProviding {
    var effectRecords: EffectRecordStore? { get }
}

/// Optional item and container indexes. With the session's `WorldStateStore` they build
/// the `InventoryRuntime` behind take, drop and container sessions.
nonisolated public protocol ItemDataProviding {
    var inventoryBaselines: InventoryBaselineResolver? { get }
    /// Slot and model data for equippable items, for the `EquipmentRuntime`. Separate,
    /// because equipping needs body templates the inventory view does not.
    var equipmentCatalog: EquipmentCatalog? { get }
    /// Recipes and stations for crafting sessions. Nil on a synthetic scene.
    var craftingCatalog: CraftingCatalog? { get }
    /// `iHoursToRespawnCell`, for harvest regrowth. Vanilla on a synthetic scene.
    var harvestRegrowth: HarvestRegrowth { get }
}

nonisolated extension ItemDataProviding {
    public var craftingCatalog: CraftingCatalog? {
        nil
    }

    public var harvestRegrowth: HarvestRegrowth {
        .vanilla
    }
}

/// Optional RACE/CLAS/NPC_ stat indexes. With the session's `WorldStateStore` they build
/// the `ActorValueRuntime` behind damage, restore and regeneration.
nonisolated public protocol ActorValueDataProviding {
    var actorValueBaselines: ActorValueBaselineResolver? { get }
}

/// Optional MGEF index, plus the base plugin its EFID links are relative to. Both nil on a
/// synthetic scene, and the magic panel then says it is unavailable.
nonisolated public protocol MagicDataProviding {
    var magicEffectStore: MagicEffectStore? { get }
    var magicItemPluginName: String? { get }
    /// Load-order SPEL and SCRL index, which the spellbook keys its spells against.
    var spellStore: SpellStore? { get }
    /// Load-order EQUP index, which answers which hands a readied spell takes.
    /// The load-order view rather than `EquipmentCatalog`'s single-plugin table,
    /// because a spell's ETYP is relative to whichever plugin authored the
    /// spell, and that need not be the one the item indexes were built from.
    var equipSlotStore: EquipSlotStore? { get }
    /// Load-order ENCH index: resolves an item's `EITM` to effects, cost and charge.
    var enchantmentStore: EnchantmentStore? { get }
}

/// Optional progression seam: the PERK index. Separate from `MagicDataProviding`, because
/// perks reach combat, prices and detection too.
nonisolated public protocol ProgressionDataProviding {
    /// Load-order PERK index, or nil on a synthetic scene, where the perk
    /// runtime reports itself unavailable rather than showing an actor who owns
    /// nothing.
    var perkStore: PerkStore? { get }

    /// Load-order AVIF index with each skill's `AVSK` parameters. Nil on a synthetic
    /// scene, where a use is counted and dropped instead of using invented numbers.
    var actorValueInformation: ActorValueInformationStore? { get }

    /// `fSkillUseCurve` and `fXPPerSkillRank` for this load order, or the documented
    /// defaults on a synthetic scene.
    var skillAdvancementSettings: SkillAdvancementSettings { get }

    /// The level curve and level-up rewards for this load order, or documented defaults.
    /// The player level lives on `ActorValueBaselineResolver.playerLevel`, the one value
    /// every `PC Level Mult` derivation reads.
    var characterLevelSettings: CharacterLevelSettings { get }
}

/// Optional social seam: the FACT and RELA indexes hostility reads. Separate, because
/// factions reach crime, dialogue and services. Nil on a synthetic scene, where every
/// actor is neutral.
nonisolated public protocol FactionDataProviding {
    /// Load-order FACT index: membership lookups and the interfaction relation index.
    var factionStore: FactionStore? { get }

    /// Load-order RELA and ASTP index: what one pair of actors is to each other.
    var relationshipStore: RelationshipStore? { get }

    /// Load-order FLST index, which flattens a vendor faction's buy/sell keyword list.
    var formListStore: FormListStore? { get }
}

/// The session data the main actor reads while the runner builds cells. The
/// `XDataProviding` protocols say which stores a conformer carries.
nonisolated public protocol WorldDataProviding {}

/// Optional script-loading seam: compiled scripts come lazily from the file system, and
/// VMAD FormIDs resolve with the cell build's master table, so both agree on identity.
/// Both values are `Sendable`.
nonisolated public protocol ScriptDataProviding {
    var scriptFileSystem: (any GameFileSource)? { get }
    var scriptFormIDResolver: FormIDResolver { get }
}

/// Optional immutable player-movement tuning resolved from active GMST data.
nonisolated public protocol MovementConfigurationProviding {
    var movementConfiguration: PlayerMovementConfiguration { get }
}

/// Optional barter factors (`fBarterMin`, `fBarterMax`) from GMST data. A synthetic scene
/// has none, and the merchant menu uses the documented vanilla defaults.
nonisolated public protocol BarterDataProviding {
    var barterPricing: BarterPricing { get }
}

/// Optional combat GMSTs (`fCombatDistance`, block settings). A synthetic scene falls back
/// to the UESP-documented numbers.
nonisolated public protocol CombatDataProviding {
    var combatSettings: CombatSettings { get }
    /// The archery GMSTs, on the same terms. Same protocol, because one GMST load at one
    /// moment resolves both.
    var archerySettings: ArcherySettings { get }
    /// The detection GMSTs, on the same terms, from the same GMST load.
    var detectionSettings: DetectionSettings { get }
    /// The `fDiffMult*` GMSTs, on the same terms.
    var difficultySettings: DifficultySettings { get }
}

nonisolated extension CombatDataProviding {
    public var difficultySettings: DifficultySettings {
        .synthetic
    }
}

/// Optional audio-record stores for the world sound director. `WeatherStore` comes via
/// `WeatherProviding.weatherSystem?.store`.
nonisolated public protocol AudioDataProviding {
    var soundStore: SoundRecordStore? { get }
    var aspcStore: AcousticSpaceStore? { get }
    /// Footstep record index (FSTS/FSTP/IPDS/IPCT) for the footstep director.
    var footstepStore: FootstepStore? { get }
    /// Music record index (MUSC/MUST) for the music director.
    var musicStore: MusicRecordStore? { get }
    /// MATT index, so the footstep readout names the surface instead of a FormID.
    var materialTypes: MaterialTypeIndex? { get }
}
