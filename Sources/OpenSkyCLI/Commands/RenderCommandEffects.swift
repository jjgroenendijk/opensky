// `render` effect flags: the image-space pass, a forced IMGS, a running IMAD, a
// membrane on the first actor, and a forced weather with its SPGD rain. They make
// the A/B captures of docs/rendering/image-space.md and visual-effects.md.

import Foundation
import OpenSkyCLIArguments
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyWorld
import simd

struct EffectCaptureOptions {
    var imageSpaceOff = false
    var imageSpace: String?
    var modifier: String?
    var modifierAt: Float = 0
    var membrane: String?
    var weather: String?
    var frames = 1

    var needsRecords: Bool {
        imageSpace != nil || modifier != nil || membrane != nil || weather != nil
    }

    static func parse(_ arguments: EffectCaptureArguments) throws -> Self {
        var options = Self()
        options.imageSpaceOff = arguments.imageSpaceOff
        options.imageSpace = arguments.imgs
        options.modifier = arguments.imad
        options.modifierAt = try number(arguments.imadAt, name: "--imad-at") ?? 0
        options.membrane = arguments.membrane
        options.weather = arguments.weather
        let frames = try number(arguments.frames, name: "--frames") ?? 1
        guard (1 ... 600).contains(frames) else {
            throw CLIError.usage("--frames expects 1-600")
        }
        options.frames = Int(frames)
        return options
    }

    private static func number(_ value: String?, name: String) throws -> Float? {
        guard let value else { return nil }
        guard let parsed = Float(value), parsed.isFinite, parsed >= 0 else {
            throw CLIError.usage("\(name) expects a number, got \(value)")
        }
        return parsed
    }
}

/// The actor a membrane capture covers and the camera that frames it.
struct MembraneSubject {
    let owner: UInt32
    let camera: SceneCamera

    /// The first actor placement in `scene`, framed from about two meters away.
    init?(scene: RenderScene) {
        let actor = (scene.opaque + scene.alphaTested)
            .filter { $0.layer == .actors }
            .flatMap(\.instances)
            .first { $0.owner != 0 }
        guard let actor else { return nil }
        let feet = SIMD3<Float>(
            actor.modelMatrix.columns.3.x,
            actor.modelMatrix.columns.3.y,
            actor.modelMatrix.columns.3.z
        )
        owner = actor.owner
        camera = SceneCamera.framing(bounds: (
            min: feet - SIMD3(50, 50, 0), max: feet + SIMD3(50, 50, 130)
        ))
    }
}

/// Where a capture's records come from, and the actor a membrane covers.
struct EffectCaptureScene {
    let context: CLIContext
    let file: ESMFile
    let worldspace: String
    let membraneOwner: UInt32?
}

extension RenderCommand {
    /// Applies `options` to a renderer built for one capture.
    static func applyEffects(
        _ options: EffectCaptureOptions, to renderer: Renderer, scene: EffectCaptureScene
    ) throws {
        let file = scene.file
        renderer.imageSpace.passEnabled = !options.imageSpaceOff
        guard options.needsRecords else { return }
        let records = EffectRecordStore(
            plugins: ActivePluginFiles.load(root: scene.context.root, baseFile: file)
        )
        renderer.session.imageSpaceLinks = ImageSpaceLinks(
            records: records,
            weatherPlugin: "skyrim.esm"
        )
        try applyWeather(options.weather, to: renderer, file: file, worldspace: scene.worldspace)
        if let name = options.imageSpace {
            guard let space = records.imageSpaces.record(editorID: name) else {
                throw CLIError.failure("no IMGS \(name)")
            }
            renderer.imageSpace.forcedBaseline = ResolvedImageSpace(
                key: ReferenceKey(resolved: space.id), record: space.record
            )
        }
        if let name = options.modifier {
            guard let adapter = records.imageSpaceAdapters.record(editorID: name) else {
                throw CLIError.failure("no IMAD \(name)")
            }
            renderer.imageSpace.modifiers.start(
                adapter.record,
                key: ReferenceKey(resolved: adapter.id)
            )
            // Each rendered frame ages it by 1/30 s too.
            renderer.imageSpace.modifiers.advance(options.modifierAt - Float(options.frames) / 30)
        }
        if let name = options.membrane {
            try applyMembrane(name, records: records, owner: scene.membraneOwner, to: renderer)
        }
    }

    private static func applyWeather(
        _ name: String?, to renderer: Renderer, file: ESMFile, worldspace: String
    ) throws {
        guard let system = WeatherSystem(file: file, worldspaceEditorID: worldspace) else { return }
        renderer.weather = system
        guard let name else { return }
        guard let weather = system.store.weathers.values.first(where: { $0.editorID == name })
        else {
            throw CLIError.failure("no WTHR \(name)")
        }
        system.forceWeather(weather.formID, transition: .instant)
    }

    private static func applyMembrane(
        _ name: String, records: EffectRecordStore, owner: UInt32?, to renderer: Renderer
    ) throws {
        guard let shader = records.effectShaders.record(editorID: name) else {
            throw CLIError.failure("no EFSH \(name)")
        }
        guard let look = MembraneLook(shader: shader.record) else {
            throw CLIError.failure("EFSH \(name) has no membrane")
        }
        guard let owner else { throw CLIError.failure("no actor in the scene for --membrane") }
        let peak = max(look.fill.fadeIn, look.edge.fadeIn) + 0.01
        try renderer.setMembranes([look.draw(on: .actor(owner), at: peak)])
    }

    /// One evidence line per capture, so a log shows what the frame held.
    static func printEffectState(_ renderer: Renderer) {
        let state = renderer.imageSpace
        let current = state.current
        let modifiers = state.modifiers.instances.map(\.name).joined(separator: ", ")
        let precipitation = renderer.precipitation.snapshot
        let baseline = state.forcedBaseline.map { $0.record.editorID ?? "?" }
            ?? state.baseline.dominantName
        print(
            "[INFO] image space: pass \(state.passEnabled ? "on" : "off"), "
                + "baseline \(baseline), "
                + "modifiers [\(modifiers)], saturation \(current.saturation), "
                + "brightness \(current.brightness), tint \(current.tint)"
        )
        print(
            "[INFO] effects: membranes drawn \(renderer.effects.lastMembraneDraws), "
                + "weather \(renderer.weather?.currentWeatherEditorID ?? "none"), "
                + "rain live \(precipitation.rainLiveCount), "
                + "snow live \(precipitation.snowLiveCount), "
                + "spgd \(renderer.precipitation.tuning.source ?? "fallback")"
        )
    }
}
