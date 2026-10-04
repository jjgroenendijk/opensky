// The race menu, map marker, fast travel, and identity natives. The menus answer
// through `PapyrusMenuBridge`, which the app sets. Signatures follow the Creation
// Kit wiki pages for `Game`, `ObjectReference`, `Actor`, `ActorBase`, and `Form`.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

/// What the menu natives reach. The app answers it.
@MainActor
public protocol PapyrusMenuBridge: AnyObject {
    func showRaceMenu(limited: Bool)
    /// True when the trip started; a refusal shows its message and returns false.
    func fastTravel(to marker: ReferenceKey) -> Bool
    func setFastTravelEnabled(_ enabled: Bool)
    func addToMap(_ marker: ReferenceKey, allowFastTravel: Bool)
    func isMapMarkerVisible(_ marker: ReferenceKey) -> Bool
    /// The player's chosen race for the player, else the actor's record race.
    func race(of actor: ReferenceKey) -> FormID?
    /// 0 male, 1 female, or nil for an unknown base.
    func sex(ofBase base: FormID) -> Int?
    func name(of form: FormID) -> String?
}

extension PapyrusNativeFunctions {
    public static func installMenus(into registry: inout PapyrusNativeRegistry) {
        game("ShowRaceMenu", into: &registry) { _, menus in
            menus.showRaceMenu(limited: false)
            return .returned(.none)
        }
        game("ShowLimitedRaceMenu", into: &registry) { _, menus in
            menus.showRaceMenu(limited: true)
            return .returned(.none)
        }
        game("EnableFastTravel", into: &registry) { call, menus in
            menus.setFastTravelEnabled(boolean(call, at: 0, default: true))
            return .returned(.none)
        }
        registry.register(PapyrusNativeFunction(
            scriptName: "Game",
            functionName: "FastTravel"
        ) { call, context in
            guard
                let world = context.world as? PapyrusWorldStateBridge, let menus = world.menus,
                let handle = objectArgument(call, at: 0),
                let marker = world.referenceKey(for: handle)
            else { return failure(call, "FastTravel needs a world and a destination") }
            _ = menus.fastTravel(to: marker)
            return .returned(.none)
        })
        installMarkerNatives(into: &registry)
        installIdentityNatives(into: &registry)
    }

    private static func installMarkerNatives(into registry: inout PapyrusNativeRegistry) {
        withReference("ObjectReference", "AddToMap", into: &registry) { call, _, menus, key in
            menus.addToMap(key, allowFastTravel: boolean(call, at: 0, default: false))
            return .returned(.none)
        }
        withReference(
            "ObjectReference",
            "IsMapMarkerVisible",
            into: &registry
        ) { _, _, menus, key in
            .returned(.boolean(menus.isMapMarkerVisible(key)))
        }
    }

    private static func installIdentityNatives(into registry: inout PapyrusNativeRegistry) {
        withReference("Actor", "GetRace", into: &registry) { _, world, menus, key in
            guard
                let race = menus.race(of: key),
                let raceKey = world.referenceKey(forFormID: race),
                let handle = world.objectHandle(for: raceKey)
            else { return .returned(.none) }
            return .returned(.object(handle))
        }
        withForm("ActorBase", "GetSex", into: &registry) { _, menus, form in
            .returned(.integer(Int32(menus.sex(ofBase: form) ?? -1)))
        }
        withForm("Form", "GetName", into: &registry) { _, menus, form in
            .returned(.string(menus.name(of: form) ?? ""))
        }
    }

    private static func game(
        _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (PapyrusNativeCall, any PapyrusMenuBridge) -> PapyrusNativeResult
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Game",
            functionName: name
        ) { call, context in
            guard let menus = (context.world as? PapyrusWorldStateBridge)?.menus else {
                return failure(call, "\(name) needs the menu bridge")
            }
            return body(call, menus)
        })
    }

    private static func withReference(
        _ script: String, _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, PapyrusWorldStateBridge, any PapyrusMenuBridge, ReferenceKey
        ) -> PapyrusNativeResult
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: script,
            functionName: name
        ) { call, context in
            guard
                let world = context.world as? PapyrusWorldStateBridge, let menus = world.menus,
                let receiver = call.receiver, let key = world.referenceKey(for: receiver)
            else { return failure(call, "\(name) needs the menu bridge and a reference") }
            return body(call, world, menus, key)
        })
    }

    private static func withForm(
        _ script: String, _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (PapyrusNativeCall, any PapyrusMenuBridge, FormID)
            -> PapyrusNativeResult
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: script,
            functionName: name
        ) { call, context in
            guard
                let world = context.world as? PapyrusWorldStateBridge, let menus = world.menus,
                let receiver = call.receiver,
                case let .plugin(plugin, objectID)? = world.referenceKey(for: receiver),
                let form = world.formIDResolver?.localFormID(
                    of: ResolvedFormID(plugin: plugin, objectID: objectID)
                )
            else { return failure(call, "\(name) needs the menu bridge and a form") }
            return body(call, menus, form)
        })
    }
}
