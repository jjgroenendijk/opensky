// The two groups of session stores `WorldDataStores` keeps apart, so it names fewer types.

import OpenSkyAIPackages
import OpenSkyCombatInterface
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyPerceptionInterface
import OpenSkyWorldInterface
public import OpenSkyWorldState

/// The spell, perk, and skill records the progression and magic runtimes start from.
nonisolated public struct WorldProgressionStores {
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
    /// Load-order AVIF index; nil on the same synthetic scenes,
    /// and then skill advancement has no parameters and reports the drop.
    public var actorValueInformation: ActorValueInformationStore?
    /// GMST-derived skill-use curve and per-rank character experience, defaulting to
    /// the documented numbers on a synthetic scene.
    public var skillAdvancementSettings: SkillAdvancementSettings = .documentedDefaults
    /// GMST-derived level curve and level-up rewards, defaulting
    /// to the documented numbers on a synthetic scene.
    public var characterLevelSettings: CharacterLevelSettings = .documentedDefaults

    public init() {}
}

/// The trade, lock, reset, relationship, and detection records.
nonisolated public struct WorldRuleStores {
    /// Equippable-item slot index; nil on the same synthetic
    /// scenes, and then equipping reports itself unavailable.
    public var equipmentCatalog: EquipmentCatalog?
    /// Load-order recipes and the item plugin's stations; nil on a synthetic scene.
    public var craftingCatalog: CraftingCatalog?
    /// GMST-derived `fBarterMin` and `fBarterMax` at the milestone's fixed
    /// Speech value, defaulting to the documented vanilla numbers.
    public var barterPricing: BarterPricing = .vanilla
    /// Lockpicking tuning, the lockpick item, and hazards; defaults on a synthetic scene.
    public var lockTrapData = LockTrapData()
    /// `iHoursToRespawnCell` and `iHoursToRespawnCellCleared`.
    public var cellResetSettings = CellResetSettings.vanilla
    /// ECZN records, for the encounter zone's "never resets" flag.
    public var encounterZoneStore: EncounterZoneStore?
    /// Load-order RELA and ASTP index; nil on the same synthetic
    /// scenes, and then no pair overrides its factions.
    public var relationshipStore: RelationshipStore?
    /// GMST-derived detection ranges, noise weights, and thresholds, defaulting to
    /// the documented numbers on a synthetic scene.
    public var detectionSettings: DetectionSettings = .synthetic

    public init() {}
}
