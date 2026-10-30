// Natives that set a flag, number, or form link no other runtime holds, and the reads
// that answer it back. They live in `ScriptedReferenceState` on the receiver's form
// (the player's for `Game`). An unset flag reads false and an unset value reads 0.
// See docs/engine/papyrus-script-state.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    /// One Bool a setter stores and an optional getter reads. The setter's first
    /// argument defaults to true, as most of them declare.
    private struct ScriptedFlag {
        let script: String
        let setter: String
        let getter: String?
        let name: String

        init(_ script: String, _ setter: String, _ getter: String, _ name: String) {
            self.script = script
            self.setter = setter
            self.getter = getter
            self.name = name
        }

        init(_ script: String, _ setter: String, _ name: String) {
            self.script = script
            self.setter = setter
            getter = nil
            self.name = name
        }
    }

    private static let scriptedFlags: [ScriptedFlag] = [
        ScriptedFlag("Actor", "SetGhost", "IsGhost", ScriptedStateName.ghost),
        ScriptedFlag(
            "Actor",
            "SetPlayerTeammate",
            "IsPlayerTeammate",
            ScriptedStateName.playerTeammate
        ),
        ScriptedFlag("Actor", "SetAlert", "IsAlerted", ScriptedStateName.alerted),
        ScriptedFlag("Actor", "SetAllowFlying", "IsAllowedToFly", ScriptedStateName.allowFlying),
        ScriptedFlag("Actor", "SetAllowFlyingEx", ScriptedStateName.allowFlying),
        ScriptedFlag("Actor", "SetIntimidated", "IsIntimidated", "intimidated"),
        ScriptedFlag("Actor", "SetBribed", "IsBribed", ScriptedStateName.bribed),
        ScriptedFlag("Actor", "SetUnconscious", "IsUnconscious", ScriptedStateName.unconscious),
        ScriptedFlag("Actor", "SetRestrained", ScriptedStateName.restrained),
        ScriptedFlag(
            "Actor", "SetNoBleedoutRecovery", "GetNoBleedoutRecovery",
            ScriptedStateName.noBleedoutRecovery
        ),
        ScriptedFlag("Actor", "SetNotShowOnStealthMeter", "notShowOnStealthMeter"),
        ScriptedFlag("Actor", "SetDontMove", "dontMove"),
        ScriptedFlag("Actor", "SetAttackActorOnSight", "attackActorOnSight"),
        ScriptedFlag("Actor", "SetHeadTracking", "headTracking"),
        ScriptedFlag("Actor", "SetPlayerResistingArrest", "resistingArrest"),
        ScriptedFlag("Actor", "AllowBleedoutDialogue", "bleedoutDialogue"),
        ScriptedFlag("Actor", "AllowPCDialogue", "pcDialogue"),
        ScriptedFlag("ObjectReference", "IgnoreFriendlyHits", "ignoreFriendlyHits"),
        ScriptedFlag("ObjectReference", "SetNoFavorAllowed", "noFavorAllowed"),
        ScriptedFlag("ActorBase", "SetEssential", ScriptedStateName.essential),
        ScriptedFlag("ActorBase", "SetInvulnerable", "invulnerable"),
        ScriptedFlag("ActorBase", "SetProtected", ScriptedStateName.protected),
        ScriptedFlag("Location", "SetCleared", "IsCleared", ScriptedStateName.cleared),
        ScriptedFlag("Cell", "SetPublic", "public"),
        ScriptedFlag("Quest", "SetActive", "IsActive", "active")
    ]

    /// One `Actor` number a setter stores; the getter reads 0 until it is set.
    private static let scriptedValues: [(setter: String, getter: String?)] = [
        ("SetAlpha", nil),
        ("SetVoiceRecoveryTime", "GetVoiceRecoveryTime"),
        ("SetCriticalStage", nil)
    ]

    /// One `Actor` form link a setter stores; `None` clears it.
    private static let scriptedForms: [(setter: String, name: String)] = [
        ("SetForcedLandingMarker", "forcedLandingMarker"),
        ("SetCrimeFaction", "crimeFaction"),
        ("SetLookAt", "lookAt")
    ]

    public static func installScriptState(into registry: inout PapyrusNativeRegistry) {
        installDoingFavor(into: &registry)
        // Landing requests are allowed by default, so the flag stores the refusal.
        scriptState(
            "Game",
            "SetAllowFlyingMountLandingRequests",
            into: &registry
        ) { call, bridge, key in
            let allows = boolean(call, at: 0, default: true)
            bridge.updateScriptedState(of: key) {
                $0.setFlag(ScriptedStateName.flyingMountLandingRefused, allows ? nil : true)
            }
            return .returned(.none)
        }
        for flag in scriptedFlags {
            scriptState(flag.script, flag.setter, into: &registry) { call, bridge, key in
                let isSet = boolean(call, at: 0, default: true)
                bridge.updateScriptedState(of: key) { $0.setFlag(flag.name, isSet ? true : nil) }
                return .returned(.none)
            }
            guard let getter = flag.getter else { continue }
            scriptState(flag.script, getter, into: &registry) { _, bridge, key in
                .returned(.boolean(bridge.scriptedState(of: key).flag(flag.name) ?? false))
            }
        }
        for value in scriptedValues {
            scriptState("Actor", value.setter, into: &registry) { call, bridge, key in
                guard let number = float(call, at: 0), number.isFinite else {
                    return failure(call, "\(value.setter) needs a finite number")
                }
                bridge.updateScriptedState(of: key) { $0.setValue(value.setter, number) }
                return .returned(.none)
            }
            guard let getter = value.getter else { continue }
            scriptState("Actor", getter, into: &registry) { _, bridge, key in
                .returned(.float(bridge.scriptedState(of: key).value(value.setter) ?? 0))
            }
        }
        for form in scriptedForms {
            scriptState("Actor", form.setter, into: &registry) { call, bridge, key in
                let link = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:))
                bridge.updateScriptedState(of: key) { $0.setForm(form.name, link) }
                return .returned(.none)
            }
        }
        scriptState("Actor", "ClearLookAt", into: &registry) { _, bridge, key in
            bridge.updateScriptedState(of: key) { $0.setForm("lookAt", nil) }
            return .returned(.none)
        }
        installKeywordData(into: &registry)
        installOwnership(into: &registry)
        installPlayerControls(into: &registry)
        installAddedForms(into: &registry)
    }

    /// `SetDoingFavor` also tells the session when the state changes, so the actor says
    /// its Favors tab line (<https://ck.uesp.net/wiki/Favors_Tab>).
    private static func installDoingFavor(into registry: inout PapyrusNativeRegistry) {
        let name = ScriptedStateName.doingFavor
        scriptState("Actor", "SetDoingFavor", into: &registry) { call, bridge, key in
            let isSet = boolean(call, at: 0, default: true)
            let was = bridge.scriptedState(of: key).flag(name) ?? false
            bridge.updateScriptedState(of: key) { $0.setFlag(name, isSet ? true : nil) }
            if was != isSet {
                bridge.storyNatives.favorStateChanged?(key, isSet)
            }
            return .returned(.none)
        }
        scriptState("Actor", "IsDoingFavor", into: &registry) { _, bridge, key in
            .returned(.boolean(bridge.scriptedState(of: key).flag(name) ?? false))
        }
    }

    /// `SetKeywordData(Keyword, float)` and `float GetKeywordData(Keyword)` on a location.
    private static func installKeywordData(into registry: inout PapyrusNativeRegistry) {
        scriptState("Location", "SetKeywordData", into: &registry) { call, bridge, key in
            guard
                let keyword = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:)),
                let number = float(call, at: 1), number.isFinite
            else { return failure(call, "SetKeywordData needs a keyword and a number") }
            let name = ScriptedStateName.keywordData(keyword)
            bridge.updateScriptedState(of: key) { $0.setValue(name, number) }
            return .returned(.none)
        }
        scriptState("Location", "GetKeywordData", into: &registry) { call, bridge, key in
            guard let keyword = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:))
            else { return failure(call, "GetKeywordData needs a keyword") }
            let state = bridge.scriptedState(of: key)
            return .returned(.float(state.value(ScriptedStateName.keywordData(keyword)) ?? 0))
        }
    }

    /// Registers a native that reads or writes the script state of its receiver's form,
    /// or of the player for a global `Game` function.
    static func scriptState(
        _ script: String, _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, PapyrusWorldStateBridge, ReferenceKey
        ) -> PapyrusNativeResult
    ) {
        let native: PapyrusNativeFunction.Body = { call, context in
            guard let bridge = context.world as? PapyrusWorldStateBridge else {
                return needsWorld(call)
            }
            if script == "Game" {
                return body(call, bridge, .player)
            }
            guard let key = call.receiver.flatMap(bridge.referenceKey(for:)) else {
                return needsWorld(call)
            }
            return body(call, bridge, key)
        }
        registry.register(PapyrusNativeFunction(
            scriptName: script,
            functionName: name,
            body: native
        ))
    }
}
