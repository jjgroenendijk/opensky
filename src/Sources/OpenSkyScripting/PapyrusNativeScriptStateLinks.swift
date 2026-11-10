// The script-state natives with more than one flag or form: ownership, the player
// controls, and the forms a script adds to a list. See docs/engine/papyrus-script-state.md.

import Foundation
public import OpenSkyCrimeInterface
public import OpenSkyFormatsESM
public import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    /// The eight control groups of `DisablePlayerControls`, in argument order, with the
    /// default each argument has there. `EnablePlayerControls` defaults every one to true.
    static let playerControls: [(name: String, disabledByDefault: Bool)] =
        PlayerControlGroup.allCases.map {
            ($0.rawValue, [.movement, .fighting, .menu, .activate].contains($0))
        }

    /// `SetActorOwner(ActorBase)`, `SetFactionOwner(Faction)`, and their reads, on a
    /// reference or a cell. One owner at a time; a None argument clears it.
    static func installOwnership(into registry: inout PapyrusNativeRegistry) {
        for script in ["ObjectReference", "Cell"] {
            for (setter, name) in [
                ("SetActorOwner", "actorOwner"),
                ("SetFactionOwner", "factionOwner")
            ] {
                scriptState(script, setter, into: &registry) { call, bridge, key in
                    let owner = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:))
                    bridge.updateScriptedState(of: key) { state in
                        state.setFlag(PapyrusWorldStateBridge.ownerSetName, true)
                        state.setForm("actorOwner", nil)
                        state.setForm("factionOwner", nil)
                        state.setForm(name, owner)
                    }
                    return .returned(.none)
                }
            }
            for (getter, wantsActor) in [("GetActorOwner", true), ("GetFactionOwner", false)] {
                scriptState(script, getter, into: &registry) { _, bridge, key in
                    let owner: ReferenceOwner?
                    if let scripted = bridge.scriptedOwner(of: key) {
                        owner = scripted
                    } else if
                        script == "ObjectReference",
                        let world = bridge.crimeNatives.crimeReporter?()?.world
                    {
                        owner = world.crimeOwner(of: key)
                    } else {
                        return .deviated(.none, .stubbed)
                    }
                    let match: ReferenceKey? = switch owner {
                    case let .actor(actor)? where wantsActor: actor
                    case let .faction(faction, _)? where !wantsActor: faction
                    default: nil
                    }
                    return .returned(match.flatMap(bridge.objectHandle(for:))
                        .map { .object($0) } ?? .none)
                }
            }
        }
    }

    /// `DisablePlayerControls`, `EnablePlayerControls`, the `Is<X>ControlsEnabled`
    /// reads, `SetInChargen`, and `SetBeastForm`. The state is kept on the player.
    static func installPlayerControls(into registry: inout PapyrusNativeRegistry) {
        for (native, disables) in [
            ("DisablePlayerControls", true),
            ("EnablePlayerControls", false)
        ] {
            scriptState("Game", native, into: &registry) { call, bridge, key in
                bridge.updateScriptedState(of: key) { state in
                    for (index, control) in playerControls.enumerated() {
                        let fallback = disables ? control.disabledByDefault : true
                        guard boolean(call, at: index, default: fallback) else { continue }
                        state.setFlag(
                            PapyrusWorldStateBridge.controlDisabledName(control.name),
                            disables ? true : nil
                        )
                    }
                }
                return .returned(.none)
            }
        }
        for control in playerControls {
            let read = "Is\(control.name)ControlsEnabled"
            scriptState("Game", read, into: &registry) { _, bridge, key in
                let state = bridge.scriptedState(of: key)
                return .returned(.boolean(state
                        .flag(PapyrusWorldStateBridge.controlDisabledName(control.name)) != true))
            }
        }
        scriptState("Game", "SetInChargen", into: &registry) { call, bridge, key in
            bridge.updateScriptedState(of: key) { state in
                for (index, name) in PapyrusWorldStateBridge.chargenFlags.enumerated() {
                    state.setFlag(name, boolean(call, at: index, default: false) ? true : nil)
                }
            }
            return .returned(.none)
        }
        scriptState("Game", "SetBeastForm", into: &registry) { call, bridge, key in
            let flag: Bool? = boolean(call, at: 0, default: false) ? true : nil
            bridge.updateScriptedState(of: key) { $0.setFlag(ScriptedStateName.beastForm, flag) }
            return .returned(.none)
        }
    }

    /// `AddForm`, `RemoveAddedForm`, and `Revert` on a form list, and `AddForm` and
    /// `Revert` on the leveled lists, whose entries keep their level and count.
    static func installAddedForms(into registry: inout PapyrusNativeRegistry) {
        for script in ["FormList", "LeveledItem", "LeveledActor", "LeveledSpell"] {
            let leveled = script != "FormList"
            scriptState(script, "AddForm", into: &registry) { call, bridge, key in
                guard let form = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:))
                else { return failure(call, "AddForm needs a form") }
                bridge.updateScriptedState(of: key) { state in
                    if !state.addedForms.contains(form) {
                        state.setAddedForms(state.addedForms + [form])
                    }
                    guard leveled else { return }
                    let level = integer(call, at: 1) ?? 1
                    let count = script == "LeveledItem" ? integer(call, at: 2) ?? 1 : 1
                    state.setValue(PapyrusWorldStateBridge.addedLevelName(form), Float(level))
                    state.setValue(PapyrusWorldStateBridge.addedCountName(form), Float(count))
                }
                if leveled {
                    bridge.publishLeveledEdits()
                }
                return .returned(.none)
            }
            scriptState(script, "Revert", into: &registry) { _, bridge, key in
                bridge.updateScriptedState(of: key) { state in
                    for form in state.addedForms where leveled {
                        state.setValue(PapyrusWorldStateBridge.addedLevelName(form), nil)
                        state.setValue(PapyrusWorldStateBridge.addedCountName(form), nil)
                    }
                    state.setAddedForms([])
                }
                if leveled {
                    bridge.publishLeveledEdits()
                }
                return .returned(.none)
            }
        }
        scriptState("FormList", "RemoveAddedForm", into: &registry) { call, bridge, key in
            let form = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:))
            bridge.updateScriptedState(of: key) { state in
                state.setAddedForms(state.addedForms.filter { $0 != form })
            }
            return .returned(.none)
        }
    }
}

extension PapyrusWorldStateBridge {
    /// The owner a script set on `key`: nil when no script set one, `.some(nil)` when a
    /// script cleared it.
    public func scriptedOwner(of key: ReferenceKey) -> ReferenceOwner?? {
        let state = scriptedState(of: key)
        guard state.flag(PapyrusWorldStateBridge.ownerSetName) == true else { return nil }
        if let actor = state.form("actorOwner") {
            return .some(.actor(actor))
        }
        return .some(state.form("factionOwner").map {
            .faction($0, requiredRank: 0)
        })
    }
}

extension PapyrusWorldStateBridge {
    /// The control groups and `SetInChargen` switches scripts set on the player. The beast
    /// form is the shell's to add.
    public var playerControlLocks: PlayerControlLocks {
        let state = scriptedState(of: playerKey)
        let flags = PapyrusWorldStateBridge.chargenFlags.map { state.flag($0) == true }
        return PlayerControlLocks(
            disabled: Set(PlayerControlGroup.allCases.filter {
                state.flag(PapyrusWorldStateBridge.controlDisabledName($0.rawValue)) == true
            }),
            savingDisabled: flags[0], waitingDisabled: flags[1], showsChargenMessage: flags[2]
        )
    }

    /// False after `DisablePlayerControls` turned movement off; the HUD reads it.
    public var isPlayerMovementEnabled: Bool {
        let name = PapyrusWorldStateBridge.controlDisabledName("Movement")
        return scriptedState(of: playerKey).flag(name) != true
    }
}
