// Condition functions that read what a script set with a native, such as `SetGhost` or
// `SetKeywordData`. The scripting module fills the snapshot on the main actor.
// See docs/engine/condition-functions.md#script-state.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

/// The script state of every form a script changed, keyed by that form.
nonisolated public struct ScriptedStateConditionResolution: ConditionResolution, Sendable {
    public static let empty = ScriptedStateConditionResolution(states: nil)

    private let states: [ReferenceKey: ScriptedReferenceState]?

    public init(states: [ReferenceKey: ScriptedReferenceState]?) {
        self.states = states
    }

    /// The state of `key`, empty when no script changed it. Nil when nothing was wired.
    public func state(of key: ReferenceKey) -> ScriptedReferenceState? {
        guard let states else { return nil }
        return states[key] ?? ScriptedReferenceState()
    }
}

nonisolated extension ConditionContext {
    public var scriptedState: ScriptedStateConditionResolution {
        get { self[resolution: ScriptedStateConditionResolution.self] }
        set { self[resolution: ScriptedStateConditionResolution.self] = newValue }
    }
}

/// The names natives store flags and values under, shared with the conditions.
nonisolated public enum ScriptedStateName: Sendable {
    public static let ghost = "ghost"
    public static let unconscious = "unconscious"
    public static let restrained = "restrained"
    public static let playerTeammate = "playerTeammate"
    public static let allowFlying = "allowFlying"
    public static let flyingMountLandingRefused = "flyingMountLandingRefused"
    public static let alerted = "alerted"
    public static let bribed = "bribed"
    public static let cleared = "cleared"
    public static let essential = "essential"
    public static let protected = "protected"
    public static let equippedShout = "equippedShout"
    public static let doingFavor = "doingFavor"
    public static let talkedToPlayer = "talkedToPlayer"
    public static let eaten = "eaten"
    /// On the player: `Game.SetBeastForm(true)` until `SetBeastForm(false)`.
    public static let beastForm = "beastForm"
    /// An actor kneeling at zero health instead of dying.
    public static let bleedingOut = "bleedingOut"
    /// `Actor.SetNoBleedoutRecovery(true)` keeps a kneeling actor down.
    public static let noBleedoutRecovery = "noBleedoutRecovery"
    /// `Actor.StartDeferredKill` holds the actor's death until `EndDeferredKill`.
    public static let deferredKill = "deferredKill"
    /// Who killed an actor, set on the victim as it dies.
    public static let killer = "killer"
    public static let destroyed = "destroyed"
    public static let destructionStage = "destructionStage"
    public static let destructionDamage = "destructionDamage"
    /// The game day this actor last caught the player pickpocketing.
    public static let pickpocketCaughtDay = "pickpocketCaughtDay"
    /// How often the player hit an actor that was not hostile to them.
    public static let friendHits = "friendHits"
    /// On the player: the last actor that attacked them.
    public static let lastHostileActor = "lastHostileActor"

    /// On the player: `Game.TeachWord` learned the word of power.
    public static func wordKnown(_ word: ReferenceKey) -> String {
        "wordKnown:\(word)"
    }

    /// On the player: the word is unlocked, by `Game.UnlockWord` or a dragon soul.
    public static func wordUnlocked(_ word: ReferenceKey) -> String {
        "wordUnlocked:\(word)"
    }

    /// On an actor: `Actor.AddShout` gave it the shout.
    public static func shout(_ shout: ReferenceKey) -> String {
        "shout:\(shout)"
    }

    /// The value `Location.SetKeywordData` stores for one keyword.
    public static func keywordData(_ keyword: ReferenceKey) -> String {
        "keywordData:\(keyword)"
    }
}

nonisolated extension ConditionFunctions {
    public static func installScriptState(_ registry: inout ConditionFunctionRegistry) {
        // The run-on's flag, false until a script sets it, as the matching native reads.
        let flags: [String: (index: UInt16, flag: String)] = [
            "GetIsAlerted": (91, ScriptedStateName.alerted),
            "GetIsGhost": (237, ScriptedStateName.ghost),
            "GetRestrained": (244, ScriptedStateName.restrained),
            "IsBribedbyPlayer": (402, ScriptedStateName.bribed),
            "GetPlayerTeammate": (453, ScriptedStateName.playerTeammate),
            "IsAllowedToFly": (698, ScriptedStateName.allowFlying),
            "IsInFavorState": (635, ScriptedStateName.doingFavor),
            "GetTalkedToPC": (50, ScriptedStateName.talkedToPlayer),
            "HasBeenEaten": (127, ScriptedStateName.eaten),
            "IsBleedingOut": (580, ScriptedStateName.bleedingOut),
            "GetNoBleedoutRecovery": (694, ScriptedStateName.noBleedoutRecovery)
        ]
        for (name, entry) in flags.sorted(by: { $0.key < $1.key }) {
            registry.register(ConditionFunction(index: entry.index, name: name) { call in
                call.referenceKey().flatMap { key in
                    Self.scriptState(call, of: key).map { Self.isTrue($0.flag(entry.flag) == true) }
                }
            })
        }
        // `ptLocation`; a location is cleared once a script calls `SetCleared`.
        registry.register(ConditionFunction(
            index: 250, name: "GetLocationCleared", parameter1: .formID
        ) { call in
            guard let location = Self.parameterKey(call, call.parameter1) else {
                return .failure(.unresolvedParameter(250))
            }
            return Self.scriptState(call, of: location).map {
                Self.isTrue($0.flag(ScriptedStateName.cleared) == true)
            }
        })
        installKeywordData(&registry)
        installShout(&registry)
        installRecordedEvents(&registry)
    }

    private static func installShout(_ registry: inout ConditionFunctionRegistry) {
        // `ptShout`: true when the run-on's equipped shout is the parameter.
        registry.register(ConditionFunction(
            index: 579, name: "GetEquippedShout", parameter1: .formID
        ) { call in
            guard let shout = Self.parameterKey(call, call.parameter1) else {
                return .failure(.unresolvedParameter(579))
            }
            return call.referenceKey().flatMap { key in
                Self.scriptState(call, of: key).map {
                    Self.isTrue($0.form(ScriptedStateName.equippedShout) == shout)
                }
            }
        })
        // OpenSky shouts no variations, and feeding plays no animation, so the actor is
        // never in the middle of it: these read 0.
        let acts: [String: UInt16] = [
            "GetCurrentShoutVariation": 676, "GetVampireFeed": 226, "GetCannibal": 227
        ]
        for (name, index) in acts.sorted(by: { $0.key < $1.key }) {
            registry.register(ConditionFunction(index: index, name: name) { call in
                call.referenceKey()
                    .flatMap { key in Self.scriptState(call, of: key).map { _ in 0 } }
            })
        }
    }

    /// Keyword data reads 0 until `SetKeywordData` stores a value, as `GetKeywordData` does.
    private static func installKeywordData(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 606, name: "GetKeywordDataForLocation", parameter1: .formID,
            parameter2: .formID
        ) { call in
            keywordData(call, index: 606, location: Self.parameterKey(call, call.parameter1))
        })
        // Parameter 1 is a location alias of the owning quest.
        registry.register(ConditionFunction(
            index: 608, name: "GetKeywordDataForAlias", parameter1: .integer, parameter2: .formID
        ) { call in
            let location = call.parameter1.flatMap(call.aliasLocation)
            return keywordData(call, index: 608, location: location.map(ReferenceKey.init))
        })
        registry.register(ConditionFunction(
            index: 651, name: "GetKeywordDataForCurrentLocation", parameter1: .formID
        ) { call in
            call.referenceKey().flatMap { reference in
                guard let current = call.context.data.currentLocation(of: reference) else {
                    return .failure(.unavailableData(.location))
                }
                return keywordData(
                    call, index: 651, location: ReferenceKey(resolved: current),
                    keyword: call.parameter1
                )
            }
        })
    }

    private static func keywordData(
        _ call: ConditionCall, index: UInt16, location: ReferenceKey?
    ) -> Result<Float, ConditionFailure> {
        keywordData(call, index: index, location: location, keyword: call.parameter2)
    }

    private static func keywordData(
        _ call: ConditionCall, index: UInt16, location: ReferenceKey?,
        keyword parameter: Condition.Parameter?
    ) -> Result<Float, ConditionFailure> {
        guard let location, let keyword = parameter.flatMap({ formKey(call, $0.asFormID) }) else {
            return .failure(.unresolvedParameter(index))
        }
        return Self.scriptState(call, of: location).map {
            $0.value(ScriptedStateName.keywordData(keyword)) ?? 0
        }
    }

    /// A keyword is a base record, never an alias fill, whatever the alias flag says.
    private static func formKey(_ call: ConditionCall, _ id: FormID) -> ReferenceKey? {
        if let target = call.context.formIDTranslation?.target {
            return ReferenceKey.resolve(id, using: target)
        }
        guard
            let plugin = call.context.data.sourcePlugin,
            let resolved = call.context.data.keywords?.resolvedID(id, fromPlugin: plugin)
        else { return nil }
        return ReferenceKey(resolved: resolved)
    }

    static func scriptState(
        _ call: ConditionCall, of key: ReferenceKey
    ) -> Result<ScriptedReferenceState, ConditionFailure> {
        guard let state = call.context.scriptedState.state(of: key) else {
            return .failure(.unavailableData(.scriptState))
        }
        return .success(state)
    }
}
