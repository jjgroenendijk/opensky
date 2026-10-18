// When a native call returns, as the Creation Kit wiki labels each one.
// See docs/engine/papyrus-vm.md#native-timing.

import Foundation

/// How long a native call takes before the script goes on.
nonisolated public enum PapyrusNativeTiming: String, Equatable, Sendable, CaseIterable {
    /// Returns in the same frame.
    case nonDelayed
    /// Returns on the next frame.
    case delayed
    /// Returns when its own condition is met, such as a wait ending.
    case latent
}

/// Which timing the VM applies to native calls.
nonisolated public enum PapyrusNativeTimingMode: Equatable, Sendable {
    /// Every native but a non-delayed one takes at least one fixed step, as in the game.
    case game
    /// Only a native that suspends itself takes time. Scripts run faster than in the game.
    case runToEnd
}

nonisolated public enum PapyrusNativeTimingTable {
    /// The timing class of one native. A native no list names is delayed, as the wiki
    /// says of every native outside the non-delayed category.
    public static func timing(of key: PapyrusNativeKey) -> PapyrusNativeTiming {
        if nonDelayed.contains(key) {
            return .nonDelayed
        }
        return latent.contains(key) ? .latent : .delayed
    }

    public static func timing(scriptName: String, functionName: String) -> PapyrusNativeTiming {
        timing(of: PapyrusNativeKey(scriptName: scriptName, functionName: functionName))
    }

    /// <https://ck.uesp.net/wiki/Category:Non-delayed_Native_Function>
    static let nonDelayed: Set<PapyrusNativeKey> = folded([
        "Alias": ["GetOwningQuest"],
        "Debug": [
            "CloseUserLog", "DumpAliasData", "OpenUserLog", "StartScriptProfiling",
            "StartStackProfiling", "StopScriptProfiling", "StopStackProfiling", "Trace",
            "TraceStack", "TraceUser"
        ],
        "Form": [
            "RegisterForAnimationEvent", "RegisterForLOS", "RegisterForSingleLOSGain",
            "RegisterForSingleLOSLost", "RegisterForSingleUpdate",
            "RegisterForSingleUpdateGameTime", "RegisterForSleep", "RegisterForTrackedStatsEvent",
            "RegisterForUpdate", "RegisterForUpdateGameTime", "StartObjectProfiling",
            "StopObjectProfiling", "UnregisterForAnimationEvent", "UnregisterForLOS",
            "UnregisterForSleep", "UnregisterForTrackedStatsEvent", "UnregisterForUpdate",
            "UnregisterForUpdateGameTime"
        ],
        "Game": ["GetForm", "GetFormFromFile"],
        "GlobalVariable": ["GetValue", "SetValue"],
        "LocationAlias": ["Clear", "ForceLocationTo", "GetLocation"],
        "Math": [
            "Abs", "Acos", "Asin", "Atan", "Ceiling", "Cos", "DegreesToRadians", "Floor", "Pow",
            "RadiansToDegrees", "Sin", "Sqrt", "Tan"
        ],
        "ObjectReference": [
            "AddInventoryEventFilter", "DisableNoWait", "EnableNoWait",
            "RemoveAllInventoryEventFilters", "RemoveInventoryEventFilter"
        ],
        "ReferenceAlias": ["Clear", "ForceRefTo", "GetReference"]
    ])

    /// <https://ck.uesp.net/wiki/Category:Latent_Functions>, vanilla scripts only.
    static let latent: Set<PapyrusNativeKey> = folded([
        "Actor": ["MoveToPackageLocation", "PathToReference", "Resurrect", "ShowGiftMenu"],
        "Debug": [
            "CenterOnCellAndWait", "GetConfigName", "GetPlatformName", "GetVersionNumber",
            "PlayerMoveToAndWait"
        ],
        "Faction": ["SendPlayerToJail"],
        "Game": [
            "AddHavokBallAndSocketConstraint",
            "GetGameSettingString",
            "RemoveHavokConstraints"
        ],
        "Keyword": ["SendStoryEventAndWait"],
        "MagicEffect": ["GetAssociatedSkill"],
        "Message": ["Show"],
        "ObjectReference": [
            "AddItem", "ApplyHavokImpulse", "DamageObject", "Delete", "DeleteWhenAble", "Disable",
            "DisableLinkChain", "DropObject", "Enable", "ForceAddRagdollToWorld",
            "ForceRemoveRagdollFromWorld", "KnockAreaEffect", "MoveTo", "MoveToIfUnloaded",
            "MoveToInteractionLocation", "MoveToMyEditorLocation", "MoveToNode",
            "PlayAnimationAndWait", "PlayImpactEffect", "PlaySyncedAnimationAndWaitSS",
            "PlayTerrainEffect", "Reset", "SetAngle", "SetMotionType", "SetPosition", "SetScale",
            "WaitForAnimationEvent"
        ],
        "Quest": ["SetCurrentStageID", "Start"],
        "ReferenceAlias": ["TryToDisable", "TryToEnable", "TryToMoveTo"],
        "Scroll": ["Cast"],
        "Sound": ["PlayAndWait"],
        "Spell": ["Cast", "RemoteCast"],
        "Utility": ["GameTimeToString", "Wait", "WaitGameTime", "WaitMenuMode"]
    ])

    private static func folded(_ functions: [String: [String]]) -> Set<PapyrusNativeKey> {
        Set(functions.flatMap { script, names in
            names.map { PapyrusNativeKey(scriptName: script, functionName: $0) }
        })
    }
}
