// Optional capability seams a `CellSceneProvider` can also conform to.
//
// A satellite of `CellBuildRunner.swift`, which sits at the strict file-length
// cap. These belong together rather than beside their own subsystems: every one
// of them answers the same question — what a provider built from real plugin
// data can hand the main thread that a synthetic scene cannot — and
// `GameViewController` reaches for them in one place, at session wire-up.
//
// Every value behind these is immutable after `init`, which is what makes
// reading one from the main thread safe while the builder itself stays confined
// to its serial queue.

import Foundation

/// Optional weather runtime a provider can expose (M7.2.2). GameViewController
/// pulls it off the provider to hand the renderer. Built once at setup from the
/// same ESM data, then read-only value types — safe to share to the main thread.
nonisolated protocol WeatherProviding {
    var weatherSystem: WeatherSystem? { get }
}

/// Optional GLOB index a provider can expose (issue #165). GameViewController
/// pairs it with the session's `WorldStateStore` to build the
/// `GlobalResolution` conditions, the clock and weather-chance selection read
/// global values through.
nonisolated protocol GlobalDataProviding {
    var globalStore: GlobalStore? { get }
}

/// Optional QUST index a provider can expose (issue #322). `GameViewController`
/// pairs it with the session's `WorldStateStore` to build the `QuestRuntime`
/// the `Quest` natives mutate and the quest script instances are started from.
/// Immutable after `init` like every other `*Store` here.
nonisolated protocol QuestDataProviding {
    var questStore: QuestStore? { get }
}

/// Optional load-order-wide LCTN index used while filling direct location
/// aliases and resolving CELL XLCN links.
nonisolated protocol LocationDataProviding {
    var locationStore: LocationStore? { get }
}

/// Optional DIAL/INFO/VTYP index a provider can expose (issue #204). The
/// dialogue runtime consumes this in 17.2; synthetic scenes leave it nil.
nonisolated protocol DialogueDataProviding {
    var dialogueStore: DialogueStore? { get }
}

/// Optional PACK/NPC_ schedule index (issue #201). The M16 gate panel pulls
/// this seam from the real provider; synthetic scenes leave it nil.
nonisolated protocol PackageDataProviding {
    var packageStore: PackageStore? { get }
}

/// Optional item + container indexes a provider can expose (issue #177).
/// `GameViewController` pairs the resolver with the session's
/// `WorldStateStore` to build the `InventoryRuntime` that take, drop and
/// container sessions run on. Immutable after `init` like every other `*Store`
/// here, so reading it from the main thread does not break the builder's queue
/// confinement.
nonisolated protocol ItemDataProviding {
    var inventoryBaselines: InventoryBaselineResolver? { get }
    /// Slot and model data for equippable items (issue #178), paired with the
    /// baselines above to build the session's `EquipmentRuntime`. Separate
    /// from the baseline resolver because equipping needs body templates the
    /// inventory view deliberately does not carry.
    var equipmentCatalog: EquipmentCatalog? { get }
}

/// Optional RACE/CLAS/NPC_ stat indexes a provider can expose (issue #194).
/// `GameViewController` pairs the resolver with the session's `WorldStateStore`
/// to build the `ActorValueRuntime` that damage, restore and regeneration run
/// on. Immutable after `init` like every other `*Resolver` here, so reading it
/// from the main thread does not break the builder's queue confinement.
nonisolated protocol ActorValueDataProviding {
    var actorValueBaselines: ActorValueBaselineResolver? { get }
}

/// Optional MGEF index a provider can expose (issue #469). The active-effect
/// runtime resolves every EFID through it, and the plugin name beside it is
/// what those links are relative to — the base plugin the item indexes were
/// built from. Both nil on a synthetic scene, and then the magic panel reports
/// itself unavailable rather than showing a convincing nothing.
nonisolated protocol MagicDataProviding {
    var magicEffectStore: MagicEffectStore? { get }
    var magicItemPluginName: String? { get }
    /// Load-order SPEL and SCRL index (issue #470), which the spellbook keys
    /// its known spells against.
    var spellStore: SpellStore? { get }
    /// Load-order EQUP index, which answers which hands a readied spell takes.
    /// The load-order view rather than `EquipmentCatalog`'s single-plugin table,
    /// because a spell's ETYP is relative to whichever plugin authored the
    /// spell, and that need not be the one the item indexes were built from.
    var equipSlotStore: EquipSlotStore? { get }
    /// Load-order ENCH index (issue #472), which resolves the `EITM` an equipped
    /// weapon or worn armour carries into an effect list, a cost and a charge.
    var enchantmentStore: EnchantmentStore? { get }
}

/// Optional progression seam a provider can expose (issue #497): the PERK index
/// the perk runtime owns perks out of and evaluates entry points against.
///
/// Its own protocol rather than another member of `MagicDataProviding`, because
/// progression is its own subsystem — perks reach combat, magic, prices and
/// detection alike — and a session that wants perks should not have to claim it
/// carries spells.
nonisolated protocol ProgressionDataProviding {
    /// Load-order PERK index, or nil on a synthetic scene, where the perk
    /// runtime reports itself unavailable rather than showing an actor who owns
    /// nothing.
    var perkStore: PerkStore? { get }

    /// Load-order AVIF index (issue #498), which skill advancement reads each
    /// skill's `AVSK` use and improve parameters out of. Nil on a synthetic
    /// scene, and then a use is counted and dropped rather than converted with
    /// invented multipliers.
    var actorValueInformation: ActorValueInformationStore? { get }

    /// `fSkillUseCurve` and `fXPPerSkillRank` as this load order resolves them
    /// (issue #498), defaulting to the documented numbers on a synthetic scene.
    var skillAdvancementSettings: SkillAdvancementSettings { get }

    /// The character-level curve and the level-up rewards as this load order
    /// resolves them (issue #499), defaulting to the documented numbers on a
    /// synthetic scene.
    ///
    /// The player level itself is *not* here: it is published on
    /// `ActorValueBaselineResolver.playerLevel`, because that is the one value
    /// every `PC Level Mult` derivation already reads and a second copy would
    /// be a second answer.
    var characterLevelSettings: CharacterLevelSettings { get }
}

/// Optional script-loading seam a provider can expose (issue #171). The
/// Papyrus world runtime resolves a script name to compiled bytecode lazily
/// through the file system, and resolves the FormIDs a VMAD property names
/// with the same master table the cell build used, so a script and the cell
/// it is attached to agree on reference identity.
///
/// Both values are immutable and thread-safe (`VirtualFileSystem` is
/// `Sendable`; `FormIDResolver` is a value), so reading them from the main
/// thread does not break the builder's queue confinement.
nonisolated protocol ScriptDataProviding {
    var scriptFileSystem: VirtualFileSystem? { get }
    var scriptFormIDResolver: FormIDResolver { get }
}

/// Optional immutable player-movement tuning resolved from active GMST data.
nonisolated protocol MovementConfigurationProviding {
    var movementConfiguration: PlayerMovementConfiguration { get }
}

/// Optional barter price factors resolved from active GMST data (issue #179).
/// Separate from `MovementConfigurationProviding` for the same reason the item
/// indexes are separate from the audio ones: a synthetic scene has no load
/// order to read `fBarterMin` and `fBarterMax` out of, and the merchant menu
/// then falls back to the documented vanilla defaults rather than to nothing.
nonisolated protocol BarterDataProviding {
    var barterPricing: BarterPricing { get }
}

/// Optional combat GMSTs resolved from active game data (issue #195).
///
/// Separate from `MovementConfigurationProviding` for the same reason
/// `BarterDataProviding` is: a synthetic scene has no load order to read
/// `fCombatDistance` and the block settings out of, and melee then falls back
/// to the UESP-documented numbers rather than to nothing.
nonisolated protocol CombatDataProviding {
    var combatSettings: CombatSettings { get }
    /// The archery GMSTs (issue #196), on the same terms. Same protocol rather
    /// than a second one because both are resolved from one GMST load and both
    /// are read at the same moment in session wire-up; splitting them would
    /// only let a provider supply one and not the other.
    var archerySettings: ArcherySettings { get }
    /// The detection GMSTs (issue #202), on the same terms again. All three
    /// families come out of one GMST load at one moment in session wire-up, and
    /// splitting them would only let a provider supply some and not others.
    var detectionSettings: DetectionSettings { get }
}

/// Optional decoded audio-record stores a provider can expose (M9.2.2).
/// GameViewController pulls these off the provider to construct the world
/// sound director alongside the audio engine. WeatherStore arrives via
/// `WeatherProviding.weatherSystem?.store`.
nonisolated protocol AudioDataProviding {
    var soundStore: SoundRecordStore? { get }
    var aspcStore: AcousticSpaceStore? { get }
    /// Footstep record index (FSTS/FSTP/IPDS/IPCT), added in issue #352 for
    /// the footstep director.
    var footstepStore: FootstepStore? { get }
    /// Music record index (MUSC/MUST), added in M9.2.3 for the music director.
    var musicStore: MusicRecordStore? { get }
    /// MATT index (issue #358), so the footstep readout can name the surface
    /// the ground contact reported rather than print a bare FormID.
    var materialTypes: MaterialTypeIndex? { get }
}
