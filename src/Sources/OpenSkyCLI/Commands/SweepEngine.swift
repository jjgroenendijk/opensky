// The headless engine the sweeps run on: the load order's quests and scripts behind the
// Papyrus world runtime, with no cell loaded and no frame drawn
// (docs/tools/headless-sweeps.md).

import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorldConditions
import OpenSkyWorldState

@MainActor
final class SweepEngine {
    let plugins: LoadOrderPlugins
    let quests: QuestStore
    let worldState = WorldStateStore()
    let bridge: PapyrusWorldStateBridge
    let world: PapyrusWorldRuntime
    let questRuntime: QuestRuntime

    init(context: CLIContext) throws {
        let loadOrder = try context.loadOrder()
        plugins = loadOrder.plugins
        let files = plugins.files
        quests = QuestStore(plugins: files)
        let locations = LocationStore(plugins: files)
        bridge = PapyrusWorldStateBridge(worldState: worldState)
        world = PapyrusWorldRuntime(runtime: PapyrusRuntime(
            files: [],
            nativeDispatch: PapyrusNativeFunctions.standardRegistry(
                context: PapyrusNativeContext(world: bridge)
            ),
            limits: .headless
        ))
        bridge.world = world
        bridge.formIDResolver = plugins.space
        bridge.stores.globals = GlobalStore(loadOrder: plugins)
        // A new game's clock; the sweeps never advance it.
        let clock = GameClock()
        bridge.natives.session.clockSource = { clock }
        world.retainFormIDResolver(plugins.space)
        var runtime = QuestRuntime(store: worldState, quests: quests, locations: locations)
        let persistent = RuntimeReferenceIndex(persistent: locations.persistentPlacements)
        runtime.referenceSearch = {
            var search = QuestReferenceSearch(
                references: .empty, origin: nil,
                context: ConditionContext(functions: .standard)
            )
            search.persistent = persistent
            return search
        }
        questRuntime = runtime
        bridge.questRuntime = runtime
        let loader = PexScriptLoader(fileSystem: context.makeFileSystem())
        world.scriptProvider = { name in attempt { try loader.load(name) } }
    }

    /// The load-order key of a record's FormID.
    func key(of id: FormID) -> ReferenceKey? {
        plugins.space.resolve(id).map(ReferenceKey.init(resolved:))
    }

    var fallbackCounts: [String: Int] {
        Dictionary(world.fallbacks.map { ($0.name, $0.count) }, uniquingKeysWith: +)
    }

    /// Runs `body`, drains the script queue, and names the fallbacks that rose meanwhile.
    /// Calls still waiting afterwards are dropped, so they do not run into the next subject.
    func fallbacksMet(_ body: () -> Void) -> [String] {
        let before = fallbackCounts
        body()
        let settled = world.drain()
        world.dropWaitingCalls()
        let met = HeadlessSweepReport.delta(before: before, after: fallbackCounts)
        return settled ? met : met + ["script queue still busy after the drain"]
    }

    /// Writes the report and the fallback counts to `out`, or to a new run directory.
    func write(report: String, name: String, out: String?) throws -> URL {
        let directory: URL
        if let out {
            directory = URL(filePath: out, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } else {
            directory = try RunDirectory.create(name)
        }
        try report.write(
            to: directory.appending(path: "report.txt"),
            atomically: true,
            encoding: .utf8
        )
        try HeadlessSweepReport.fallbackTable(world.fallbacks)
            .write(
                to: directory.appending(path: "fallbacks.tsv"),
                atomically: true,
                encoding: .utf8
            )
        return directory
    }
}
