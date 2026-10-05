// Env-gated idle runtime over the user's install. The selector runs over every
// idle marker of a few inns for the nearest resident NPC, the 0_Master idles
// resolve to clips and props, and one NPC plays its marker idle in a capture
// under .logs/idle-runtime/.

import Foundation
import MetalKit
@testable import OpenSkyActorsInterface
@testable import OpenSkyConditions
@testable import OpenSkyFormatsAnimation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldState
import simd
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct IdleRuntimeRealDataTests {
    private static let masterBehavior = "actors\\character\\behaviors\\0_master.hkx"

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func masterIdlesResolveToClipsAndProps() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let files = VirtualFileSystem(root: root)
        let store = IdleStore(plugins: ActivePluginFiles.load(root: root))
        let resolver = IdlePlaybackResolver(files: files, animatedObjects: store.animatedObjects)
        let bones = try Set(HKASkeleton.skeletons(in: HKXFile(data: files.contents(
            forPath: "meshes\\actors\\character\\character assets\\skeleton.hkx"
        ))).flatMap(\.boneNames))
        var paths: [String: Int] = [:]
        var attached: [String: Int] = [:]
        var unboundBones: Set<String> = []
        for idle in store.idles.records
            where idle.record.fileName?.lowercased() == Self.masterBehavior
        {
            let plan = resolver.plan(for: idle)
            let path = IdleReadout.pathText(plan.path)
            paths[path.hasPrefix("graph event") ? "graph event" : path, default: 0] += 1
            if case let .attached(editorID, _, bone) = plan.prop {
                attached[editorID, default: 0] += 1
                if !bones.contains(bone) {
                    unboundBones.insert(bone)
                }
            }
        }
        let report = paths.sorted { $0.value > $1.value }.map { "\($0.value) \($0.key)" }
            + attached.sorted { $0.key < $1.key }.map { "prop \($0.key): \($0.value) idles" }
            + ["prop bones missing from skeleton.hkx: \(unboundBones.sorted())"]
        try report.joined(separator: "\n").write(
            to: RepositoryLogs.createdDirectory("idle-runtime").appending(path: "plans.log"),
            atomically: true, encoding: .utf8
        )
        #expect(paths["graph event", default: 0] >= 780, "\(paths)")
        #expect(attached.values.reduce(0, +) >= 45, "\(attached)")
        #expect(unboundBones.isEmpty)
    }

    private struct Pick {
        let actor: RuntimeReferenceEntry
        let plan: IdlePlaybackPlan
        let idle: String

        var hasProp: Bool {
            if case .attached = plan.prop {
                return true
            }
            return false
        }
    }

    /// Inns with many idle markers. The first one is the selection gate.
    private static let inns = [
        "WhiterunBanneredMare", "RiverwoodSleepingGiantInn", "SolitudeWinkingSkeever",
        "WindhelmCandlehearthHall", "MarkarthSilverBloodInn"
    ]

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func everyInnMarkerSelectsWithATraceAndAnNPCPlaysOne() throws {
        let install = try RealDataInstall.load()
        let builder = install.sceneBuilder(readsLooseFiles: true)
        let root = try #require(RealDataEnvironment.dataRoot)
        let store = IdleStore(plugins: ActivePluginFiles.load(root: root, baseFile: install.file))
        let resolver = IdlePlaybackResolver(
            files: install.fileSystem, animatedObjects: store.animatedObjects
        )
        var lines: [String] = []
        // An idle with a prop is preferred, so the capture shows it riding its bone.
        var pick: Pick?
        var fallback: Pick?
        for (index, inn) in Self.inns.enumerated() where pick == nil || index == 0 {
            let cell = try #require(ESMWalk.record(withEditorID: inn, in: install.file))
            let scene = try builder.buildInteriorScene(cellFormID: FormID(cell.formID))
            let context = Self.conditionContext(scene: scene, builder: builder, file: install.file)
            let picks = try selectAtEveryMarker(in: context, store: store, resolver: resolver) {
                lines.append("\(inn) \($0)")
            }
            if index == 0 {
                try #require(picks.selected >= 3, "selections: \(picks.selected)")
            }
            pick = pick ?? picks.playable.first(where: \.hasProp)
            fallback = fallback ?? picks.playable.first
        }
        let logs = try RepositoryLogs.createdDirectory("idle-runtime")
        try lines.joined(separator: "\n").write(
            to: logs.appending(path: "inns.log"), atomically: true, encoding: .utf8
        )
        let found = try #require(pick ?? fallback, "no marker chose a playable idle")
        try capture(found, builder: builder, install: install, logs: logs)
    }

    /// Runs each marker's selection for the nearest resident NPC.
    @MainActor
    private func selectAtEveryMarker(
        in context: ConditionContext,
        store: IdleStore,
        resolver: IdlePlaybackResolver,
        log: (String) -> Void
    ) throws -> (selected: Int, playable: [Pick]) {
        let entries = context.references.sortedEntries()
        let actors = entries.filter { $0.placedActor != nil }
        var selected = 0
        var playable: [Pick] = []
        for entry in entries {
            guard
                let placed = entry.placedReference,
                let marker = store.markers.resolve(placed.base, fromPlugin: "Skyrim.esm"),
                let actor = actors.min(by: {
                    Self.distance($0, placed.placement.position)
                        < Self.distance($1, placed.placement.position)
                })
            else { continue }
            let selection = Self.selector(store: store, context: context, actor: actor.key).select(
                entries: store.idles(of: marker),
                order: IdleCore.selectionOrder(of: marker.record),
                startIndex: 0, played: [], random: { _ in 0 }
            )
            #expect(selection.trace.count >= store.idles(of: marker).count)
            let plan = selection.chosen.map(resolver.plan(for:))
            selected += selection.chosen == nil ? 0 : 1
            log("\(marker.record.editorID ?? "?") for \(actor.key): "
                + "\(selection.chosen?.record.editorID ?? "nothing"), "
                + "\(plan.map { IdleReadout.pathText($0.path) } ?? "-"), "
                + "trace \(selection.trace.map { IdleReadout.verdictText($0.verdict) })")
            if let plan, plan.clipPath != nil, let idle = selection.chosen?.record.editorID {
                playable.append(Pick(actor: actor, plan: plan, idle: idle))
            }
        }
        return (selected, playable)
    }

    /// The facts the app gives a resident actor: nothing out in the left hand,
    /// and the child flag of its race.
    private static func conditionContext(
        scene: CellScene,
        builder: CellSceneBuilder,
        file: ESMFile
    ) -> ConditionContext {
        let resolvers = builder.actorResolversBuildingIfNeeded(localized: true)
        var states: [ReferenceKey: ActorConditionState] = [:]
        for entry in scene.references.sortedEntries() {
            guard let placed = entry.placedActor else { continue }
            let race = (try? resolvers.template.resolve(base: placed.base))?.race.value
                .flatMap { ESMWalk.record(withFormID: $0.rawValue, in: file) }
                .flatMap { try? Race(record: $0, localized: true) }
            states[entry.key] = ActorConditionState(
                current: ActorValues(repeating: 100), maximums: ActorValues(repeating: 100),
                isChild: race?.flags.contains(.child) ?? false, leftHandOut: .nothing
            )
        }
        var context = ConditionContext()
        context.references = scene.references
        context.actors = ActorStateResolution(states: states)
        return context
    }

    private static func selector(store: IdleStore, context: ConditionContext, actor: ReferenceKey)
        -> IdleSelector
    {
        var context = context
        context.subject = actor
        let base = context
        return IdleSelector(store: store) { idle in
            var evaluator = ConditionEvaluator(context: base)
            return evaluator.firstFailure(in: idle.conditions).map(evaluator.functionName(of:))
        }
    }

    /// The NPC alone, standing and then at the middle of its idle with the prop
    /// on, so the frame shows only the idle. `.logs/idle-runtime/` holds both.
    @MainActor
    private func capture(
        _ pick: Pick,
        builder: CellSceneBuilder,
        install: RealDataInstall,
        logs: URL
    ) throws {
        let placed = try #require(pick.actor.placedActor)
        let resolvers = builder.actorResolversBuildingIfNeeded(localized: true)
        let visual = try resolvers.visual.resolve(
            appearance: resolvers.template.resolve(base: placed.base)
        )
        let assembly = ActorAssembler(provider: install.meshes).assemble(
            placed: placed,
            visual: visual
        )
        let playback = try builder.makeAnimationPlayback(assembly: assembly).get()
        var scenes = [RenderScene(
            instances: assembly.renderPlacements(at: assembly.transform),
            animations: [playback]
        )]
        // The prop goes through the same overlay the streamer draws it with.
        if case let .attached(_, modelPath, bone) = pick.plan.prop {
            let skeleton = try install.meshes.loadActorSkeleton(
                path: playback.clip.skeletonMeshPath
            ).get()
            let prop = try install.meshes.loadActorAttachment(
                path: modelPath, bone: bone, skeleton: skeleton
            ).get()
            scenes.append(.actorProp(prop.model, on: playback))
        }
        let clip = try ActorAnimationClipLoader.clip(
            skeletonMeshPath: playback.clip.skeletonMeshPath,
            animationPath: #require(pick.plan.clipPath),
            readHKX: { try HKXFile(data: install.fileSystem.contents(forPath: $0)) }
        )
        let renderer = try Self.renderer(
            RenderScene(merging: scenes),
            transform: assembly.transform,
            device: install.device
        )
        let standing = try renderer.renderOffscreen(width: 800, height: 800, animationTime: 1.5)
        let time = clip.animation.duration * 0.5
        playback.play(clip, startingAt: 0, forSeconds: clip.animation.duration)
        let idling = try renderer.renderOffscreen(width: 800, height: 800, animationTime: time)
        try FrameScreenshot.write(texture: standing, to: logs.appending(path: "standing.png"))
        try FrameScreenshot.write(texture: idling, to: logs.appending(path: "idling.png"))
        let changed = RenderedPixels.changedCount(
            RenderedPixels.read(standing), RenderedPixels.read(idling)
        )
        print("[INFO] \(pick.idle) on \(pick.actor.key): \(changed) changed pixels, "
            + "served by \(IdleReadout.pathText(pick.plan.path)), "
            + "prop \(IdleReadout.propText(pick.plan.prop))")
        #expect(changed > 2000, "the idle moved only \(changed) pixels")
    }

    @MainActor
    private static func renderer(
        _ scene: RenderScene,
        transform: float4x4,
        device: any MTLDevice
    ) throws -> Renderer {
        let feet = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let target = feet + SIMD3<Float>(0, 0, 70)
        let camera = SceneCamera(
            eye: target + simd_normalize(SIMD3<Float>(-1, -1, 0.3)) * 240,
            target: target,
            sunDirection: SceneCamera.demo.sunDirection,
            sunColor: SceneCamera.demo.sunColor,
            ambientColor: SceneCamera.demo.ambientColor
        )
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 800, height: 800), device: device)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(view: view, scene: scene, camera: camera)
    }

    private static func distance(_ entry: RuntimeReferenceEntry, _ point: SIMD3<Float>) -> Float {
        entry.placedActor
            .map { simd_distance($0.placement.position, point) } ?? .greatestFiniteMagnitude
    }
}
