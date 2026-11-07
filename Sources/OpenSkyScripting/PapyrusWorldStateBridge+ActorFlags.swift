// An actor's `ACBS` flags as the game reads them now: the record, then what scripts
// and running quest aliases changed (ActorFlagOverrides). Death, the HUD, conditions,
// and natives all read this one answer. See docs/engine/papyrus-script-state.md.

public import OpenSkyActorsInterface
public import OpenSkyFormatsESM
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface

extension PapyrusWorldStateBridge {
    static let playerBase = FormID(0x7)

    /// The flags, or nil when the actor is not known. `record` replaces the base's own
    /// flags, such as a leveled actor's rolled template; a base with neither has none.
    public func actorFlags(
        of key: ReferenceKey, record: ActorBase.Flags? = nil
    ) -> ActorBase.Flags? {
        let base = key == .player ? Self.playerBase : baseObject(of: key)
        guard let base else { return nil }
        let flags = record ?? menus?.recordFlags(ofBase: base) ?? []
        return actorFlagOverrides(of: key, base: base).applied(to: flags)
    }

    public func actorFlagOverrides(of key: ReferenceKey, base: FormID) -> ActorFlagOverrides {
        var overrides = ActorFlagOverrides()
        let own = scriptedState(of: key)
        overrides.script(.ghost, own.flag(ScriptedStateName.ghost))
        overrides.script(
            .notShowOnStealthMeter, own.flag(ScriptedStateName.notShowOnStealthMeter)
        )
        if let baseKey = referenceKey(forFormID: base) {
            let state = scriptedState(of: baseKey)
            overrides.script(.essential, state.flag(ScriptedStateName.essential))
            overrides.script(.protected, state.flag(ScriptedStateName.protected))
            overrides.script(.invulnerable, state.flag(ScriptedStateName.invulnerable))
        }
        let aliasFlags = questRuntime?.aliasResolution().aliasFlags(holding: key) ?? []
        if aliasFlags.contains(.essential) {
            overrides.fromAliases.insert(.essential)
        }
        if aliasFlags.contains(.protected) {
            overrides.fromAliases.insert(.protected)
        }
        return overrides
    }
}
