// The script-state natives with more than one flag or form: ownership, the player
// controls, and the forms a script adds to a list. See docs/engine/papyrus-script-state.md.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    /// The eight control groups of `DisablePlayerControls`, in argument order, with the
    /// default each argument has there. `EnablePlayerControls` defaults every one to true.
    static let playerControls: [(name: String, disabledByDefault: Bool)] =
        PlayerControlGroup.allCases.map {
            ($0.rawValue, [.movement, .fighting, .menu, .activate].contains($0))
        }

    /// The flags `SetInChargen` sets, in argument order.
    static let chargenFlags = ["chargenNoSaving", "chargenNoWaiting", "chargenMessage"]

    static func controlDisabledName(_ control: String) -> String {
        "controlDisabled:\(control)"
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
                        state.setFlag(ownerSetName, true)
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
                        state.setFlag(controlDisabledName(control.name), disables ? true : nil)
                    }
                }
                return .returned(.none)
            }
        }
        for control in playerControls {
            let read = "Is\(control.name)ControlsEnabled"
            scriptState("Game", read, into: &registry) { _, bridge, key in
                let state = bridge.scriptedState(of: key)
                return .returned(.boolean(state.flag(controlDisabledName(control.name)) != true))
            }
        }
        scriptState("Game", "SetInChargen", into: &registry) { call, bridge, key in
            bridge.updateScriptedState(of: key) { state in
                for (index, name) in chargenFlags.enumerated() {
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
    /// `Revert` on the leveled lists. A leveled entry keeps its form, not its level or count.
    static func installAddedForms(into registry: inout PapyrusNativeRegistry) {
        for script in ["FormList", "LeveledItem", "LeveledActor", "LeveledSpell"] {
            scriptState(script, "AddForm", into: &registry) { call, bridge, key in
                guard let form = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:))
                else { return failure(call, "AddForm needs a form") }
                bridge.updateScriptedState(of: key) { state in
                    guard !state.addedForms.contains(form) else { return }
                    state.setAddedForms(state.addedForms + [form])
                }
                return .returned(.none)
            }
            scriptState(script, "Revert", into: &registry) { _, bridge, key in
                bridge.updateScriptedState(of: key) { $0.setAddedForms([]) }
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

    static let ownerSetName = "ownerSet"
}

extension PapyrusWorldStateBridge {
    /// The owner a script set on `key`: nil when no script set one, `.some(nil)` when a
    /// script cleared it.
    public func scriptedOwner(of key: ReferenceKey) -> ReferenceOwner?? {
        let state = scriptedState(of: key)
        guard state.flag(PapyrusNativeFunctions.ownerSetName) == true else { return nil }
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
        let flags = PapyrusNativeFunctions.chargenFlags.map { state.flag($0) == true }
        return PlayerControlLocks(
            disabled: Set(PlayerControlGroup.allCases.filter {
                state.flag(PapyrusNativeFunctions.controlDisabledName($0.rawValue)) == true
            }),
            savingDisabled: flags[0], waitingDisabled: flags[1], showsChargenMessage: flags[2]
        )
    }

    /// False after `DisablePlayerControls` turned movement off; the HUD reads it.
    public var isPlayerMovementEnabled: Bool {
        let name = PapyrusNativeFunctions.controlDisabledName("Movement")
        return scriptedState(of: playerKey).flag(name) != true
    }
}
