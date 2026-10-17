// The names of dialogue topic subtypes, from the `sTopicSubtypeText<tab><name>` string
// settings. The SNAM codes and names are UESP "Skyrim Mod:Mod File Format/DIAL".
// See docs/formats/dialogue.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct TopicSubtypeTexts: Equatable, Sendable {
    /// Resolved names by SNAM code. A code with no name reads as itself.
    public var names: [FourCC: String] = [:]

    public static let vanilla = Self()

    public init() {}

    public func name(of subtype: FourCC?) -> String? {
        subtype.map { names[$0] ?? $0.description }
    }

    public static func resolve(
        store: GameSettingStore, text: GameTextResolver = { _ in nil }
    ) -> Self {
        var settings = vanilla
        for (code, suffix) in settingSuffixes {
            if let name = store.text("sTopicSubtypeText\(suffix)").flatMap({ text($0) }) {
                settings.names[code] = name
            }
        }
        return settings
    }

    /// The dialogue tab and the subtype name each setting joins. The six Dragonborn
    /// flying-mount codes have no setting.
    static let settingSuffixes: [FourCC: String] = [
        "ACAC": "MiscellaneousActorCollidewithActor",
        "ACYI": "CombatAcceptYield",
        "AGRE": "FavorsAgree",
        "ALIL": "DetectionAlertIdle",
        "ALKL": "CombatAllyKilled",
        "ALTC": "DetectionAlertToCombat",
        "ALTN": "DetectionAlertToNormal",
        "ASKF": "FavorDialogueAskFavor",
        "ASKG": "FavorDialogueAskGift",
        "ASNC": "CombatAssaultNC",
        "ASSA": "CombatAssault",
        "ATCK": "CombatAttack",
        "AVTH": "CombatAvoidThreat",
        "BAEX": "ServiceBarterExit",
        "BASH": "CombatBash",
        "BLED": "CombatBleedOut",
        "BLOC": "CombatBlock",
        "BREA": "MiscellaneousEnterSprintBreath",
        "BRIB": "FavorDialogueBribe",
        "COLO": "DetectionCombatToLost",
        "COTN": "DetectionCombatToNormal",
        "CUST": "PlayerDialogueCustom",
        "DEOB": "MiscellaneousDestroyObject",
        "DETH": "CombatDeath",
        "DFDA": "DetectionDetectFriendDie",
        "ENBZ": "MiscellaneousEnterBowZoomBreath",
        "EXBZ": "MiscellaneousExitBowZoomBreath",
        "FAVO": "FavorDialogueFavor",
        "FEXT": "FavorsExitFavorState",
        "FIWE": "MiscellaneousShootBow",
        "FLAT": "FavorDialogueFlatter",
        "FLEE": "CombatFlee",
        "FOLL": "FavorDialogueFollow",
        "FRJT": "FavorDialogueReject",
        "FVDL": "FavorDialogueCustom",
        "GBYE": "MiscellaneousGoodbye",
        "GIFF": "FavorDialogueGift",
        "GRNT": "MiscellaneousCombatGrunt",
        "GRST": "CombatGroupStrategy",
        "HELO": "MiscellaneousHello",
        "HIT_": "CombatHit",
        "IDAT": "MiscellaneousSharedInfo",
        "IDLE": "MiscellaneousIdle",
        "INTI": "FavorDialogueIntimidate",
        "JUMP": "MiscellaneousJump",
        "KNOO": "MiscellaneousKnockOverObject",
        "LOIL": "DetectionLostIdle",
        "LOOB": "MiscellaneousLockedObject",
        "LOTC": "DetectionLostToCombat",
        "LOTN": "DetectionLostToNormal",
        "LWBS": "MiscellaneousLeaveWaterBreath",
        "MREF": "FavorsMoralRefusal",
        "MUNC": "CombatMurderNC",
        "MURD": "CombatMurder",
        "NOTA": "DetectionNormalToAlert",
        "NOTC": "DetectionNormalToCombat",
        "NOTI": "MiscellaneousNoticeCorpse",
        "OBCO": "MiscellaneousObserveCombat",
        "OUTB": "MiscellaneousOutofBreath",
        "PCPS": "MiscellaneousPlayerCastProjectileSpell",
        "PCSH": "MiscellaneousPlayerShout",
        "PCSS": "MiscellaneousPlayerCastSelfSpell",
        "PFGT": "PlayerDialogueForceGreet",
        "PICC": "CombatPickpocketCombat",
        "PICN": "CombatPickpocketNC",
        "PICT": "MiscellaneousPickpocketTopic",
        "PIRN": "MiscellaneousPlayerinIronSights",
        "POAT": "CombatPowerAttack",
        "PURS": "MiscellaneousPursueIdleTopic",
        "RCEX": "ServiceRechargeExit",
        "RECH": "ServiceRecharge",
        "REEX": "ServiceRepairExit",
        "REFU": "FavorsRefuse",
        "REPA": "ServiceRepair",
        "RUMO": "PlayerDialogueRumors",
        "SCEN": "SceneDialogueCustom",
        "SERU": "ServiceServiceRefusal",
        "SHOW": "FavorsShow",
        "SHRE": "FavorDialogueShowRelationships",
        "STEA": "CombatSteal",
        "STFN": "CombatStealFromNC",
        "STOF": "MiscellaneousStandonFurniture",
        "SWMW": "MiscellaneousSwingMeleeWeapon",
        "TAUT": "CombatTaunt",
        "TITG": "MiscellaneousTimeToGo",
        "TRAI": "ServiceTraining",
        "TRAN": "CombatTrespassAgainstNC",
        "TRAV": "ServiceTravel",
        "TRES": "CombatTrespass",
        "TREX": "ServiceTrainingExit",
        "VPEL": "CombatVoicePowerEndLong",
        "VPES": "CombatVoicePowerEndShort",
        "VPSL": "CombatVoicePowerStartLong",
        "VPSS": "CombatVoicePowerStartShort",
        "WTCR": "CombatWereTransformCrime",
        "YIEL": "CombatYield",
        "ZKEY": "MiscellaneousZKeyObject"
    ]
}
