// The data scenes and the story manager read at runtime: the SCEN and SM node
// indexes, and the load order the `.seq` pass walks. See docs/engine/scenes.md
// and docs/engine/story-manager.md.

import OpenSkyFormatsESM
import OpenSkyGameData

/// One active plugin and its masters, which give its `.seq` FormIDs their meaning.
nonisolated public struct StoryPlugin: Equatable, Sendable {
    public let name: String
    public let masters: [String]

    public init(name: String, masters: [String]) {
        self.name = name
        self.masters = masters
    }
}

nonisolated public struct StoryData: Sendable {
    /// Load-order SCEN index. Nil on a synthetic scene.
    public var scenes: SceneStore?
    /// Load-order SMBN, SMQN, and SMEN index.
    public var storyManager: StoryManagerStore?
    /// Active plugins, lowest priority first.
    public var plugins: [StoryPlugin]

    public init(
        scenes: SceneStore? = nil,
        storyManager: StoryManagerStore? = nil,
        plugins: [StoryPlugin] = []
    ) {
        self.scenes = scenes
        self.storyManager = storyManager
        self.plugins = plugins
    }

    /// - Parameter plugins: the active plugins, lowest priority first.
    public static func load(plugins: [(name: String, file: ESMFile)]) -> StoryData {
        StoryData(
            scenes: SceneStore(plugins: plugins),
            storyManager: StoryManagerStore(plugins: plugins),
            plugins: plugins.map { plugin in
                let header = try? PluginHeader(tes4: plugin.file.tes4)
                return StoryPlugin(name: plugin.name, masters: header?.masters ?? [])
            }
        )
    }
}

/// Scene and story-manager data. A synthetic scene answers empty data.
nonisolated public protocol StoryDataProviding {
    var storyData: StoryData { get }
}
