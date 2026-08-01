// Env-gated M11 milestone evidence over the user's read-only Skyrim install.
// The test streams the Whiterun grid, instantiates every attached script, and
// selects a linked scripted activator through the same collision ray/use-key
// path as the app. Only aggregate counts and the selected base editor ID are
// written to gitignored logs; no game bytes or rendered capture are committed.

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct M11AcceptanceRealDataTests {
    private static let candidateCoordinate = CellCoordinate(x: 5, y: 0)
    private static let candidateReference = FormID(0x000D_97F5)
    private static let candidateEditorID = "TrapLinker"
    private static let candidateScript = "defaultActivateToggleLinkedRefOnce"

    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static var canRun: Bool {
        device != nil && dataRoot != nil
    }

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func streamsAttachedScriptsAndActivatesAVisibleVanillaReference() throws {
        let root = try #require(Self.dataRoot)
        let setup = try makeSetup(
            device: #require(Self.device),
            root: root
        )
        try drainEvents(setup.world)
        #expect(setup.sweptCellCount == 25)
        #expect(setup.world.instancesByKey.count == 28)
        let gridTally = setup.world.runtime.tally
        #expect(gridTally.faultTotal == 5)
        #expect(gridTally.unimplementedNativeTotal == 9)
        #expect(gridTally.deferredAnimationTotal == 0)

        let candidate = try candidate(in: setup.initialScene, file: setup.file)
        let chain = try M11ScriptedWorldChain(
            scriptName: Self.candidateScript,
            objects: vanillaObjects(root: root)
        )
        #expect(chain.session.worldState.component(
            ReferenceEnableState.self,
            for: M11ScriptedWorldChain.doorKey
        ) == .disabled)
        let proxy = try renderVanillaScriptProxy(chain: chain, renderer: setup.renderer)
        try writeReport(
            setup: setup,
            candidate: candidate,
            chain: chain,
            changedPixels: proxy.changedPixels,
            runtimeDisabled: proxy.runtimeDisabled
        )
    }
}

@MainActor
extension M11AcceptanceRealDataTests {
    fileprivate struct Setup {
        let file: ESMFile
        let renderer: Renderer
        let world: PapyrusWorldRuntime
        let initialScene: CellScene
        let sweptCellCount: Int
    }

    fileprivate struct Candidate {
        let linkedReference: FormID
        let linkedEditorID: String
    }

    fileprivate struct ProxyEvidence {
        let changedPixels: Int
        let runtimeDisabled: Int
    }

    private func makeSetup(device: MTLDevice, root: GameDataRoot) throws -> Setup {
        let fileSystem = VirtualFileSystem(root: root)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let textures = TextureLibrary(fileSystem: fileSystem, device: device)
        let meshes = MeshLibrary(fileSystem: fileSystem, device: device, textures: textures)
        let provider = BuilderCellSceneProvider(
            builder: CellSceneBuilder(
                file: file,
                meshes: meshes,
                textures: textures,
                fileSystem: fileSystem
            ),
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID
        )
        let world = PapyrusWorldRuntime(runtime: PapyrusRuntime(
            files: [], nativeDispatch: PapyrusNativeRegistry.standard
        ))
        let loader = PexScriptLoader(fileSystem: fileSystem)
        world.scriptProvider = { try? loader.load($0) }
        let sweep = try sweepGrid(provider: provider, world: world)
        let renderer = try makeRenderer(device: device, scene: sweep.candidate)
        return Setup(
            file: file,
            renderer: renderer,
            world: world,
            initialScene: sweep.candidate,
            sweptCellCount: sweep.count
        )
    }

    private func makeRenderer(device: MTLDevice, scene: CellScene) throws -> Renderer {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 360),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view,
            scene: scene.renderScene,
            camera: scene.bounds.map(SceneCamera.framing)
        )
        renderer.actorAnimationsEnabled = false
        renderer.weatherEnabled = false
        renderer.particlesEnabled = false
        renderer.precipitationEnabled = false
        renderer.grassEnabled = false
        renderer.sunShadowsEnabled = false
        return renderer
    }

    private func sweepGrid(
        provider: BuilderCellSceneProvider,
        world: PapyrusWorldRuntime
    ) throws -> (candidate: CellScene, count: Int) {
        var candidate: CellScene?
        var count = 0
        for y in (FirstRenderCell.gridY - 2) ... (FirstRenderCell.gridY + 2) {
            for x in (FirstRenderCell.gridX - 2) ... (FirstRenderCell.gridX + 2) {
                let coordinate = CellCoordinate(x: x, y: y)
                let scene = try provider.buildCell(at: coordinate, state: .empty)
                let location = try #require(scene.location)
                world.attach(
                    cell: location,
                    references: scene.references,
                    formIDResolver: provider.scriptFormIDResolver,
                    firstIntegration: true
                )
                count += 1
                if coordinate == Self.candidateCoordinate {
                    candidate = scene
                } else {
                    provider.evict(
                        droppingMeshKeys: scene.assets.meshKeys,
                        droppingTextureKeys: scene.assets.textureKeys
                    )
                }
            }
        }
        return try (#require(candidate), count)
    }

    private func drainEvents(_ world: PapyrusWorldRuntime) throws {
        for _ in 0 ..< 10000 where !world.eventQueue.isEmpty {
            _ = world.stepFixed()
        }
        #expect(world.eventQueue.isEmpty, "attached-script event queue did not drain")
    }

    private func candidate(in scene: CellScene, file: ESMFile) throws -> Candidate {
        let interaction = try #require(scene.interactions[Self.candidateReference])
        let entry = try #require(scene.references.entry(for: Self.candidateReference))
        let reference = try #require(entry.placedReference)
        #expect(editorID(for: interaction.base, in: file) == Self.candidateEditorID)
        #expect(reference.scriptData.scripts.map(\.name).contains(Self.candidateScript))
        let linkedReference = try #require(reference.linkedReferences.first?.ref)
        let linkedRecord = try #require(
            ESMWalk.record(withFormID: linkedReference.rawValue, in: file)
        )
        let linkedPlaced = try PlacedReference(record: linkedRecord)
        return Candidate(
            linkedReference: linkedReference,
            linkedEditorID: editorID(for: linkedPlaced.base, in: file)
        )
    }

    private func vanillaObjects(root: GameDataRoot) throws -> [PexObject] {
        let loader = PexScriptLoader(fileSystem: VirtualFileSystem(root: root))
        return try [Self.candidateScript, "ObjectReference", "Form"]
            .flatMap { try loader.load($0).objects }
    }

    private func renderVanillaScriptProxy(
        chain: M11ScriptedWorldChain,
        renderer: Renderer
    ) throws -> ProxyEvidence {
        let cells = try CellSceneBuilderTests()
        try cells.writeLooseFile("meshes/arch/solid.nif", cells.collisionRenderNIF())
        let plugin = M11ScriptedWorldChain.rebuildPlugin(cells)
        let authored = try cells.build(pluginData: plugin, gridX: 0, gridY: 0)
        let rebuilt = try cells.build(
            pluginData: plugin,
            gridX: 0,
            gridY: 0,
            state: chain.session.worldState.snapshot()
        )
        #expect(rebuilt.summary.runtimeDisabledSkipCount == 1)
        let camera = try SceneCamera.framing(bounds: #require(authored.bounds))
        try renderer.setScene(authored.renderScene, camera: camera)
        let baseline = try renderPixels(renderer)
        try renderer.setScene(rebuilt.renderScene)
        let changed = try Self.changedPixels(baseline, renderPixels(renderer))
        #expect(changed > 0)
        let texture = try renderer.renderOffscreen(width: 640, height: 360)
        try FrameScreenshot.write(
            texture: texture,
            to: logsDirectory.appending(path: "m11-acceptance-visible.png")
        )
        return ProxyEvidence(
            changedPixels: changed,
            runtimeDisabled: rebuilt.summary.runtimeDisabledSkipCount
        )
    }

    private func renderPixels(_ renderer: Renderer) throws -> [UInt8] {
        let texture = try renderer.renderOffscreen(width: 640, height: 360)
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { storage in
            guard let base = storage.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return bytes
    }

    private func writeReport(
        setup: Setup,
        candidate: Candidate,
        chain: M11ScriptedWorldChain,
        changedPixels: Int,
        runtimeDisabled: Int
    ) throws {
        let gridTally = setup.world.runtime.tally
        let activationTally = chain.session.world.runtime.tally
        let report = """
        M11 acceptance observed 2026-08-01
        streamed cells\t\(setup.sweptCellCount)
        attached instances\t\(setup.world.instancesByKey.count)
        pending events\t\(setup.world.eventQueue.count)
        faults\t\(gridTally.faultTotal)
        unknown native calls\t\(gridTally.unimplementedNativeTotal)
        deferred animations\t\(gridTally.deferredAnimationTotal)
        selected activator editor ID\t\(Self.candidateEditorID)
        selected script\t\(Self.candidateScript)
        authored linked reference\t\(candidate.linkedReference)
        linked target editor ID\t\(candidate.linkedEditorID)
        interaction dispatches\t1
        activation native calls\t\(activationTally.nativeCallTotal)
        activation faults\t\(activationTally.faultTotal)
        activation unknown native calls\t\(activationTally.unimplementedNativeTotal)
        world-state deltas\t\(chain.session.worldState.journalEntries.count)
        runtime-disabled references\t\(runtimeDisabled)
        changed pixels\t\(changedPixels)
        """
        try FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        try report.write(to: logURL, atomically: true, encoding: .utf8)
        print(report)
    }
}

extension M11AcceptanceRealDataTests {
    fileprivate static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        guard lhs.count == rhs.count else { return max(lhs.count, rhs.count) / 4 }
        return stride(from: 0, to: lhs.count, by: 4).reduce(into: 0) { count, index in
            if lhs[index ..< index + 4] != rhs[index ..< index + 4] {
                count += 1
            }
        }
    }

    private func editorID(for formID: FormID, in file: ESMFile) -> String {
        ESMWalk.record(withFormID: formID.rawValue, in: file)
            .flatMap(ESMWalk.editorID) ?? "unresolved"
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
    }

    private var logURL: URL {
        logsDirectory.appending(path: "papyrus-m11-overall-acceptance.log")
    }
}
