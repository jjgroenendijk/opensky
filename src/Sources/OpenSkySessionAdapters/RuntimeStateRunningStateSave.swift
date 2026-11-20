// The running state a save keeps beside the world state: the idle each actor plays,
// the scripted moves, and the social timers. Each lives in its coordinator while the
// game runs. A save writes it into the store just before the snapshot, and a load
// takes it back out (docs/engine/runtime-state.md#save-and-load).

import OpenSkyFormatsESM
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `RuntimeStateRunningStateSave` reads from the session.
@MainActor
public protocol RuntimeStateRunningStateHost: AnyObject, SendableMetatype {
    var idleWorld: any IdleWorldPort { get }
    var scripts: any ScriptPort { get }
    var storyManager: any StoryManagerPort { get }
    var storyWorld: any StoryWorldPort { get }
    var worldState: any WorldStateStorePort { get }
}

@MainActor
public enum RuntimeStateRunningStateSave {
    /// Replaces the saved components with what the coordinators hold now.
    public static func store(from game: any RuntimeStateRunningStateHost) {
        let store = game.worldState
        replace(with: game.idleWorld.idles.savedIdlePlays(), in: store)
        replace(with: game.scripts.bridge?.savedTranslations() ?? [:], in: store)
        let social = game.storyManager.social.state.saved(now: game.storyWorld.sceneSeconds)
        replace(with: social, in: store)
    }

    /// Hands the saved components to the coordinators and clears them from the store,
    /// where they would only go stale.
    public static func restore(into game: any RuntimeStateRunningStateHost) {
        let store = game.worldState
        game.idleWorld.idles.restoreIdlePlays(take(SavedIdlePlay.self, from: store))
        game.scripts.bridge?.restoreTranslations(take(SavedTranslation.self, from: store))
        let social = take(SavedSocialState.self, from: store)
        game.storyManager.social.restore(SocialState(
            saved: social, now: game.storyWorld.sceneSeconds
        ))
    }

    static func replace<Component: WorldStateComponent>(
        with values: [ReferenceKey: Component], in store: any WorldStateStorePort
    ) {
        for key in store.sortedDirtyKeys()
            where values[key] == nil && store.component(Component.self, for: key) != nil
        {
            store.reset(Component.componentKind, for: key)
        }
        for key in values.keys.sorted() {
            if let value = values[key] {
                store.set(value, for: key)
            }
        }
    }

    static func take<Component: WorldStateComponent>(
        _ type: Component.Type, from store: any WorldStateStorePort
    ) -> [ReferenceKey: Component] {
        var taken: [ReferenceKey: Component] = [:]
        for key in store.sortedDirtyKeys() {
            guard let value = store.component(type, for: key) else { continue }
            taken[key] = value
            store.reset(Component.componentKind, for: key)
        }
        return taken
    }
}
