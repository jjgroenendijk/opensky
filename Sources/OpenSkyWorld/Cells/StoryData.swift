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
    /// Base-plugin SCEN index, in the FormID space of the quest store. Nil on a
    /// synthetic scene.
    public var scenes: SceneStore?
    /// Base-plugin SMBN, SMQN, and SMEN index, for the same reason.
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

    public static func load(root: GameDataRoot, baseFile: ESMFile, baseName: String) -> StoryData {
        let base = [(name: baseName, file: baseFile)]
        return StoryData(
            scenes: SceneStore(plugins: base),
            storyManager: StoryManagerStore(plugins: base),
            plugins: ActivePluginFiles.load(root: root, baseFile: baseFile).map { plugin in
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
