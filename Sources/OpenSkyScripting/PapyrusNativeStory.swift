// `Keyword.SendStoryEvent` and the `Scene` natives. The receiver is a base form,
// mapped back to its FormID through the session resolver. The story manager and
// the scene runtime answer through `PapyrusStoryBridge`, which the app sets.
// See docs/engine/story-manager.md and docs/engine/scenes.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

/// What the story and scene natives reach. The app answers it.
@MainActor
public protocol PapyrusStoryBridge: AnyObject {
    /// Fires one event. True when it started a quest.
    func sendStoryEvent(_ event: StoryEventData) -> Bool
    /// True when the scene plays afterwards.
    func startScene(_ scene: FormID) -> Bool
    func stopScene(_ scene: FormID)
    func isScenePlaying(_ scene: FormID) -> Bool
}

extension PapyrusNativeFunctions {
    public static func installStory(into registry: inout PapyrusNativeRegistry) {
        // `SendStoryEvent(Location akLoc = None, ObjectReference akRef1 = None,
        // ObjectReference akRef2 = None, int aiValue1 = 0, int aiValue2 = 0)`
        // (<https://ck.uesp.net/wiki/SendStoryEvent_-_Keyword>). The walk is
        // synchronous, so the wait form returns at once.
        for (name, returnsStarted) in [("SendStoryEvent", false), ("SendStoryEventAndWait", true)] {
            registerStory(&registry, script: "Keyword", name) { call, world, keyword in
                let event = storyEvent(call, world: world, keyword: keyword)
                let started = world.story?.sendStoryEvent(event) ?? false
                return .returned(returnsStarted ? .boolean(started) : .none)
            }
        }
        // `Start()` and `ForceStart()` (<https://ck.uesp.net/wiki/Scene_Script>).
        // ForceStart does not stop the actors' other scenes, because nothing tracks them.
        for name in ["Start", "ForceStart"] {
            registerStory(&registry, script: "Scene", name) { _, world, scene in
                _ = world.story?.startScene(scene)
                return .returned(.none)
            }
        }
        registerStory(&registry, script: "Scene", "Stop") { _, world, scene in
            world.story?.stopScene(scene)
            return .returned(.none)
        }
        registerStory(&registry, script: "Scene", "IsPlaying") { _, world, scene in
            .returned(.boolean(world.story?.isScenePlaying(scene) ?? false))
        }
    }

    private static func storyEvent(
        _ call: PapyrusNativeCall,
        world: PapyrusWorldStateBridge,
        keyword: FormID
    ) -> StoryEventData {
        var event = StoryEventData(event: "SCPT")
        event.keyword = keyword
        if
            let handle = objectArgument(call, at: 0), case let .plugin(name, objectID)? =
            world.referenceKey(for: handle)
        {
            event.location1 = ResolvedFormID(plugin: name, objectID: objectID)
        }
        event.actor1 = objectArgument(call, at: 1).flatMap { world.referenceKey(for: $0) }
        event.actor2 = objectArgument(call, at: 2).flatMap { world.referenceKey(for: $0) }
        event.value1 = integer(call, at: 3).map(Float.init) ?? 0
        event.value2 = integer(call, at: 4).map(Float.init) ?? 0
        return event
    }

    /// Resolves the receiver to its FormID, or fails with the reason.
    private static func registerStory(
        _ registry: inout PapyrusNativeRegistry,
        script: String,
        _ name: String,
        body: @escaping @MainActor (
            PapyrusNativeCall, PapyrusWorldStateBridge, FormID
        ) -> PapyrusNativeResult
    ) {
        let native = PapyrusNativeFunction(
            scriptName: script,
            functionName: name
        ) { call, context in
            guard
                let world = context.world as? PapyrusWorldStateBridge,
                let receiver = call.receiver,
                case let .plugin(plugin, objectID)? = world.referenceKey(for: receiver),
                let formID = world.formIDResolver?.localFormID(
                    of: ResolvedFormID(plugin: plugin, objectID: objectID)
                )
            else {
                return failure(
                    call,
                    "\(call.functionName) needs a world runtime and a form receiver"
                )
            }
            return body(call, world, formID)
        }
        registry.register(native)
    }
}
