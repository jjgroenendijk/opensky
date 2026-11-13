// One install entry point for the headless native families.

import Foundation
import OpenSkyScriptingInterface

public enum PapyrusNativeFunctions: PapyrusNativeArguments {
    public static func install(into registry: inout PapyrusNativeRegistry) {
        PapyrusNativeFunctions.DebugNatives.installDebug(into: &registry)
        PapyrusNativeFunctions.UtilityNatives.installUtility(into: &registry)
        PapyrusNativeFunctions.MathNatives.installMath(into: &registry)
        PapyrusNativeFunctions.AnimationNatives.installDeferredAnimation(into: &registry)
        PapyrusNativeFunctions.ObjectReferenceNatives.installObjectReference(into: &registry)
        PapyrusNativeFunctions.UpdateTimersNatives.installUpdateTimers(into: &registry)
        PapyrusNativeFunctions.GlobalVariableNatives.installGlobalVariable(into: &registry)
        PapyrusNativeFunctions.GameNatives.installGame(into: &registry)
        PapyrusNativeFunctions.StatsNatives.installStats(into: &registry)
        PapyrusNativeFunctions.QuestNatives.installQuest(into: &registry)
        PapyrusNativeFunctions.ActorNatives.installActor(into: &registry)
        PapyrusNativeFunctions.SpellNatives.installSpell(into: &registry)
        PapyrusNativeFunctions.PerkNatives.installPerk(into: &registry)
        PapyrusNativeFunctions.SkillNatives.installSkill(into: &registry)
        PapyrusNativeFunctions.LevelNatives.installLevel(into: &registry)
        PapyrusNativeFunctions.CrimeNatives.installCrime(into: &registry)
        PapyrusNativeFunctions.GuardNatives.installGuard(into: &registry)
        PapyrusNativeFunctions.BarterNatives.installBarter(into: &registry)
        PapyrusNativeFunctions.FactionNatives.installFaction(into: &registry)
        PapyrusNativeFunctions.FactionRelationsNatives.installFactionRelations(into: &registry)
        PapyrusNativeFunctions.ShoutsNatives.installShouts(into: &registry)
        PapyrusNativeFunctions.InventoryFiltersNatives.installInventoryFilters(into: &registry)
        PapyrusNativeFunctions.LockNatives.installLock(into: &registry)
        PapyrusNativeFunctions.TrapNatives.installTrap(into: &registry)
        PapyrusNativeFunctions.FormListNatives.installFormList(into: &registry)
        PapyrusNativeFunctions.StoryNatives.installStory(into: &registry)
        PapyrusNativeFunctions.PresentationNatives.installPresentation(into: &registry)
        PapyrusNativeFunctions.MenusNatives.installMenus(into: &registry)
        PapyrusNativeFunctions.ReferenceAliasNatives.installReferenceAlias(into: &registry)
        PapyrusNativeFunctions.VehicleNatives.installVehicle(into: &registry)
        PapyrusNativeFunctions.FurnitureNatives.installFurniture(into: &registry)
        PapyrusNativeFunctions.InventoryNatives.installInventory(into: &registry)
        PapyrusNativeFunctions.AlchemyNatives.installAlchemy(into: &registry)
        PapyrusNativeFunctions.WorldPlaceNatives.installWorldPlace(into: &registry)
        PapyrusNativeFunctions.ScriptStateNatives.installScriptState(into: &registry)
        PapyrusNativeFunctions.EffectsNatives.installEffects(into: &registry)
        PapyrusNativeFunctions.MusicNatives.installMusic(into: &registry)
        PapyrusNativeFunctions.MountsNatives.installMounts(into: &registry)
        PapyrusNativeFunctions.SneakNatives.installSneak(into: &registry)
        PapyrusNativeFunctions.CellFogNatives.installCellFog(into: &registry)
        PapyrusNativeFunctions.ActiveMagicEffectNatives.installActiveMagicEffect(into: &registry)
        PapyrusNativeFunctions.ActorAwarenessNatives.installActorAwareness(into: &registry)
        PapyrusNativeFunctions.TranslationNatives.installTranslation(into: &registry)
        PapyrusNativeFunctions.ReferenceStateNatives.installReferenceState(into: &registry)
        PapyrusNativeFunctions.ActorStateNatives.installActorState(into: &registry)
        PapyrusNativeFunctions.WeatherNatives.installWeather(into: &registry)
        PapyrusNativeFunctions.ConditionTwinsNatives.installConditionTwins(into: &registry)
        PapyrusNativeFunctions.LineOfSightNatives.installLineOfSight(into: &registry)
        PapyrusNativeFunctions.TrackedStatsNatives.installTrackedStats(into: &registry)
        PapyrusNativeFunctions.SleepNatives.installSleep(into: &registry)
        PapyrusNativeFunctions.StateChangesNatives.installStateChanges(into: &registry)
        PapyrusNativeFunctions.WorldReadsNatives.installWorldReads(into: &registry)
        PapyrusNativeFunctions.FindReferencesNatives.installFindReferences(into: &registry)
        PapyrusNativeFunctions.SpellRecordsNatives.installSpellRecords(into: &registry)
        PapyrusNativeFunctions.SkyNatives.installSky(into: &registry)
        PapyrusNativeFunctions.GameSessionNatives.installGameSession(into: &registry)
        PapyrusNativeFunctions.ActorRulesNatives.installActorRules(into: &registry)
        PapyrusNativeFunctions.ReferenceRulesNatives.installReferenceRules(into: &registry)
        PapyrusNativeFunctions.HavokConstraintsNatives.installHavokConstraints(into: &registry)
    }
}

extension PapyrusNativeFunctions {
    public static var standardRegistry: PapyrusNativeRegistry {
        standardRegistry(context: PapyrusNativeContext())
    }

    /// The standard registry over a caller-supplied context, so a world-aware session
    /// installs the same natives with `PapyrusNativeContext.world` set.
    public static func standardRegistry(context: PapyrusNativeContext) -> PapyrusNativeRegistry {
        var registry = PapyrusNativeRegistry(context: context)
        install(into: &registry)
        return registry
    }
}

/// The native families, one per file.
extension PapyrusNativeFunctions {
    enum ActiveMagicEffectNatives: PapyrusNativeArguments {}
    enum ActorAwarenessNatives: PapyrusNativeArguments {}
    enum ActorNatives: PapyrusNativeArguments {}
    enum ActorRulesNatives: PapyrusNativeArguments {}
    enum ActorStateNatives: PapyrusNativeArguments {}
    enum ActorValuesNatives: PapyrusNativeArguments {}
    enum AlchemyNatives: PapyrusNativeArguments {}
    enum AnimationNatives: PapyrusNativeArguments {}
    enum AnimationVariablesNatives: PapyrusNativeArguments {}
    enum BarterNatives: PapyrusNativeArguments {}
    enum CellFogNatives: PapyrusNativeArguments {}
    enum ConditionTwinsNatives: PapyrusNativeArguments {}
    enum CrimeNatives: PapyrusNativeArguments {}
    enum DebugNatives: PapyrusNativeArguments {}
    enum DestructionNatives: PapyrusNativeArguments {}
    enum EffectsNatives: PapyrusNativeArguments {}
    enum FactionNatives: PapyrusNativeArguments {}
    enum FactionRelationsNatives: PapyrusNativeArguments {}
    enum FindReferencesNatives: PapyrusNativeArguments {}
    enum FormListNatives: PapyrusNativeArguments {}
    enum FurnitureNatives: PapyrusNativeArguments {}
    enum GameNatives: PapyrusNativeArguments {}
    enum GameSessionNatives: PapyrusNativeArguments {}
    enum GlobalVariableNatives: PapyrusNativeArguments {}
    enum GuardNatives: PapyrusNativeArguments {}
    enum HavokConstraintsNatives: PapyrusNativeArguments {}
    enum InventoryFiltersNatives: PapyrusNativeArguments {}
    enum InventoryNatives: PapyrusNativeArguments {}
    enum LevelNatives: PapyrusNativeArguments {}
    enum LineOfSightNatives: PapyrusNativeArguments {}
    enum LockNatives: PapyrusNativeArguments {}
    enum MathNatives: PapyrusNativeArguments {}
    enum MenusNatives: PapyrusNativeArguments {}
    enum MountsNatives: PapyrusNativeArguments {}
    enum MusicNatives: PapyrusNativeArguments {}
    enum ObjectReferenceLinksNatives: PapyrusNativeArguments {}
    enum ObjectReferenceMotionNatives: PapyrusNativeArguments {}
    enum ObjectReferenceNatives: PapyrusNativeArguments {}
    enum PerkNatives: PapyrusNativeArguments {}
    enum PresentationNatives: PapyrusNativeArguments {}
    enum QuestNatives: PapyrusNativeArguments {}
    enum ReferenceAliasNatives: PapyrusNativeArguments {}
    enum ReferenceRulesNatives: PapyrusNativeArguments {}
    enum ReferenceStateNatives: PapyrusNativeArguments {}
    enum ScriptStateLinksNatives: PapyrusNativeArguments {}
    enum ScriptStateNatives: PapyrusNativeArguments {}
    enum ShoutsNatives: PapyrusNativeArguments {}
    enum SkillNatives: PapyrusNativeArguments {}
    enum SkyNatives: PapyrusNativeArguments {}
    enum SleepNatives: PapyrusNativeArguments {}
    enum SneakNatives: PapyrusNativeArguments {}
    enum SoundNatives: PapyrusNativeArguments {}
    enum SpellNatives: PapyrusNativeArguments {}
    enum SpellRecordsNatives: PapyrusNativeArguments {}
    enum StateChangesNatives: PapyrusNativeArguments {}
    enum StatsNatives: PapyrusNativeArguments {}
    enum StoryNatives: PapyrusNativeArguments {}
    enum SubGraphsNatives: PapyrusNativeArguments {}
    enum TrackedStatsNatives: PapyrusNativeArguments {}
    enum TranslationNatives: PapyrusNativeArguments {}
    enum TrapMotionNatives: PapyrusNativeArguments {}
    enum TrapNatives: PapyrusNativeArguments {}
    enum TrapStubsNatives: PapyrusNativeArguments {}
    enum TrapWorldNatives: PapyrusNativeArguments {}
    enum UpdateTimersNatives: PapyrusNativeArguments {}
    enum UtilityNatives: PapyrusNativeArguments {}
    enum VehicleNatives: PapyrusNativeArguments {}
    enum WeatherNatives: PapyrusNativeArguments {}
    enum WorldPlaceNatives: PapyrusNativeArguments {}
    enum WorldReadsNatives: PapyrusNativeArguments {}
}
