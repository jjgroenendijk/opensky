// Change flag bits per change form type, from UESP "Skyrim Mod:ChangeFlags" (Skyrim SE
// 1.5.97). See docs/formats/ess-change-forms.md#change-flags.

import Foundation

nonisolated public enum ESSChangeFlag: Sendable {
    public static let formFlags: UInt32 = 0x0000_0001

    /// REFR, ACHR, and the projectile and hazard types.
    public enum Reference: Sendable {
        public static let move: UInt32 = 0x0000_0002
        public static let havokMove: UInt32 = 0x0000_0004
        public static let cellChanged: UInt32 = 0x0000_0008
        public static let scale: UInt32 = 0x0000_0010
        public static let inventory: UInt32 = 0x0000_0020
        public static let extraOwnership: UInt32 = 0x0000_0040
        public static let baseObject: UInt32 = 0x0000_0080
        public static let promoted: UInt32 = 0x0200_0000
        public static let extraActivatingChildren: UInt32 = 0x0400_0000
        public static let leveledInventory: UInt32 = 0x0800_0000
        public static let animation: UInt32 = 0x1000_0000
        public static let extraEncounterZone: UInt32 = 0x2000_0000
        public static let extraCreatedOnly: UInt32 = 0x4000_0000
        public static let extraGameOnly: UInt32 = 0x8000_0000
    }

    /// Every reference type except ACHR.
    public enum Object: Sendable {
        public static let extraItemData: UInt32 = 0x0000_0400
        public static let extraAmmo: UInt32 = 0x0000_0800
        public static let extraLock: UInt32 = 0x0000_1000
        public static let doorExtraTeleport: UInt32 = 0x0002_0000
        public static let empty: UInt32 = 0x0020_0000
        public static let openDefaultState: UInt32 = 0x0040_0000
        public static let openState: UInt32 = 0x0080_0000
    }

    public enum Actor: Sendable {
        public static let lifeState: UInt32 = 0x0000_0400
        public static let extraPackageData: UInt32 = 0x0000_0800
        public static let extraMerchantContainer: UInt32 = 0x0000_1000
        public static let extraDismemberedLimbs: UInt32 = 0x0002_0000
        public static let leveledActor: UInt32 = 0x0004_0000
        public static let dispositionModifiers: UInt32 = 0x0008_0000
        public static let tempModifiers: UInt32 = 0x0010_0000
        public static let damageModifiers: UInt32 = 0x0020_0000
        public static let overrideModifiers: UInt32 = 0x0040_0000
        public static let permanentModifiers: UInt32 = 0x0080_0000
    }

    /// The `NPC_` base record.
    public enum ActorBase: Sendable {
        public static let baseData: UInt32 = 0x0000_0002
        public static let attributes: UInt32 = 0x0000_0004
        public static let aiData: UInt32 = 0x0000_0008
        public static let spellList: UInt32 = 0x0000_0010
        public static let fullName: UInt32 = 0x0000_0020
        public static let factions: UInt32 = 0x0000_0040
        public static let skills: UInt32 = 0x0000_0200
        public static let npcClass: UInt32 = 0x0000_0400
        public static let face: UInt32 = 0x0000_0800
        public static let defaultOutfit: UInt32 = 0x0000_1000
        public static let sleepOutfit: UInt32 = 0x0000_2000
        public static let gender: UInt32 = 0x0100_0000
        public static let race: UInt32 = 0x0200_0000
    }

    public enum Quest: Sendable {
        public static let flags: UInt32 = 0x0000_0002
        public static let scriptDelay: UInt32 = 0x0000_0004
        public static let alreadyRun: UInt32 = 0x0400_0000
        public static let instances: UInt32 = 0x0800_0000
        public static let runData: UInt32 = 0x1000_0000
        public static let objectives: UInt32 = 0x2000_0000
        public static let script: UInt32 = 0x4000_0000
        public static let stages: UInt32 = 0x8000_0000
    }

    public enum Topic: Sendable {
        public static let saidOnce: UInt32 = 0x8000_0000
    }

    /// The flags each type's decoder reads, in UESP's names.
    public static func names(forType signature: String) -> [UInt32: String] {
        var names: [UInt32: String] = [formFlags: "FORM_FLAGS"]
        switch signature {
        case "NPC_": names.merge(actorBaseNames) { $1 }
        case "QUST": names.merge(questNames) { $1 }
        case "INFO": names[Topic.saidOnce] = "TOPIC_SAIDONCE"
        case "ACHR": names.merge(referenceNames.merging(actorNames) { $1 }) { $1 }
        default:
            if ESSChangeFormType(signature: signature)?.isReference == true {
                names.merge(referenceNames.merging(objectNames) { $1 }) { $1 }
            }
        }
        return names
    }

    private static let referenceNames: [UInt32: String] = [
        Reference.move: "REFR_MOVE", Reference.havokMove: "REFR_HAVOK_MOVE",
        Reference.cellChanged: "REFR_CELL_CHANGED", Reference.scale: "REFR_SCALE",
        Reference.inventory: "REFR_INVENTORY", Reference.extraOwnership: "REFR_EXTRA_OWNERSHIP",
        Reference.baseObject: "REFR_BASEOBJECT", Reference.promoted: "REFR_PROMOTED",
        Reference.extraActivatingChildren: "REFR_EXTRA_ACTIVATING_CHILDREN",
        Reference.leveledInventory: "REFR_LEVELED_INVENTORY",
        Reference.animation: "REFR_ANIMATION",
        Reference.extraEncounterZone: "REFR_EXTRA_ENCOUNTER_ZONE",
        Reference.extraCreatedOnly: "REFR_EXTRA_CREATED_ONLY",
        Reference.extraGameOnly: "REFR_EXTRA_GAME_ONLY"
    ]

    private static let objectNames: [UInt32: String] = [
        Object.extraItemData: "OBJECT_EXTRA_ITEM_DATA", Object.extraAmmo: "OBJECT_EXTRA_AMMO",
        Object.extraLock: "OBJECT_EXTRA_LOCK", Object.doorExtraTeleport: "DOOR_EXTRA_TELEPORT",
        Object.empty: "OBJECT_EMPTY", Object.openDefaultState: "OBJECT_OPEN_DEFAULT_STATE",
        Object.openState: "OBJECT_OPEN_STATE"
    ]

    private static let actorNames: [UInt32: String] = [
        Actor.lifeState: "ACTOR_LIFESTATE", Actor.extraPackageData: "ACTOR_EXTRA_PACKAGE_DATA",
        Actor.extraMerchantContainer: "ACTOR_EXTRA_MERCHANT_CONTAINER",
        Actor.extraDismemberedLimbs: "ACTOR_EXTRA_DISMEMBERED_LIMBS",
        Actor.leveledActor: "ACTOR_LEVELED_ACTOR",
        Actor.dispositionModifiers: "ACTOR_DISPOSITION_MODIFIERS",
        Actor.tempModifiers: "ACTOR_TEMP_MODIFIERS",
        Actor.damageModifiers: "ACTOR_DAMAGE_MODIFIERS",
        Actor.overrideModifiers: "ACTOR_OVERRIDE_MODIFIERS",
        Actor.permanentModifiers: "ACTOR_PERMANENT_MODIFIERS"
    ]

    private static let actorBaseNames: [UInt32: String] = [
        ActorBase.baseData: "ACTOR_BASE_DATA", ActorBase.attributes: "ACTOR_BASE_ATTRIBUTES",
        ActorBase.aiData: "ACTOR_BASE_AIDATA", ActorBase.spellList: "ACTOR_BASE_SPELLLIST",
        ActorBase.fullName: "ACTOR_BASE_FULLNAME", ActorBase.factions: "ACTOR_BASE_FACTIONS",
        ActorBase.skills: "NPC_SKILLS", ActorBase.npcClass: "NPC_CLASS",
        ActorBase.face: "NPC_FACE", ActorBase.defaultOutfit: "NPC_DEFAULT_OUTFIT",
        ActorBase.sleepOutfit: "NPC_SLEEP_OUTFIT", ActorBase.gender: "NPC_GENDER",
        ActorBase.race: "NPC_RACE"
    ]

    private static let questNames: [UInt32: String] = [
        Quest.flags: "QUEST_FLAGS", Quest.scriptDelay: "QUEST_SCRIPT_DELAY",
        Quest.alreadyRun: "QUEST_ALREADY_RUN", Quest.instances: "QUEST_INSTANCES",
        Quest.runData: "QUEST_RUNDATA", Quest.objectives: "QUEST_OBJECTIVES",
        Quest.script: "QUEST_SCRIPT", Quest.stages: "QUEST_STAGES"
    ]

    /// A flag's UESP name for `signature`, or its hex value.
    public static func name(of flag: UInt32, type signature: String) -> String {
        names(forType: signature)[flag] ?? String(format: "0x%08X", flag)
    }
}
