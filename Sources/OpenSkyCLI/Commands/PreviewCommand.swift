// `preview`: one record, reference, cell, or mesh rendered offscreen. Each view writes
// a PNG and a JSON report; report.json lists them. A blank view exits 1.
// Pipeline: docs/tools/preview-render.md.

import Foundation
import Metal
import OpenSkyCLIArguments
import OpenSkyPreview
import OpenSkyRendering
import OpenSkyWorld

enum PreviewCommand {
    static func run(context: CLIContext, arguments: PreviewArguments) throws {
        let options = try options(arguments)
        let request: PreviewRequest
        do {
            request = try options.request()
        } catch {
            throw CLIError.usage(error.description)
        }
        let shadingOff = try EffectCaptureOptions.shadingSettings(arguments.shadingOff)
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            throw CLIError.failure("no Metal 4 GPU available")
        }
        let builder = try RenderCommand.makeBuilder(context: context, device: device)
        let scene: PreviewScene
        do {
            scene = try PreviewSceneBuilder(builder: builder).build(request)
        } catch {
            throw CLIError.failure(error.description)
        }
        let frames = try PreviewRenderJob.render(
            scene, request: request,
            sources: PreviewRenderSources(
                device: device, loadOrder: builder.pluginLoadOrder, fileSystem: builder.fileSystem
            )
        ) { renderer in
            for setting in shadingOff {
                renderer.shadingTerms.subtract(setting.term)
            }
        }
        let report = PreviewReport(
            target: scene.target, stage: scene.stage, request: request, focus: scene.focus,
            failures: scene.failures, measures: frames.map(\.measure)
        )
        try write(frames, report: report, to: directory(arguments.out))
        if let blank = report.views.first(where: \.blank) {
            throw CLIError.failure(PreviewError.nothingDrew(view: blank.view).description)
        }
    }

    private static func options(_ arguments: PreviewArguments) throws -> PreviewOptions {
        var options = PreviewOptions()
        options.record = arguments.record
        options.reference = arguments.reference
        options.mesh = arguments.mesh
        options.cell = arguments.cell
        options.worldspace = arguments.grid.worldspace
        options.x = try RenderCommand.int32(arguments.grid.x, name: "--x")
        options.y = try RenderCommand.int32(arguments.grid.y, name: "--y")
        options.stage = arguments.stage
        options.focus = arguments.focus
        options.angles = arguments.angles
        options.yaw = try number(arguments.yaw, name: "--yaw")
        options.pitch = try number(arguments.pitch, name: "--pitch")
        options.distance = try number(arguments.distance, name: "--distance")
        options.timeOfDay = try RenderCommand.parseTimeOfDay(arguments.timeOfDay)
        options.weather = arguments.weather
        (options.width, options.height) = try RenderCommand.parseSize(arguments.size)
        return options
    }

    private static func number(_ value: String?, name: String) throws -> Float? {
        guard let value else { return nil }
        guard let number = Float(value), number.isFinite else {
            throw CLIError.usage("\(name) expects a number, got \(value)")
        }
        return number
    }

    private static func directory(_ out: String?) throws -> URL {
        guard let out else { return try RunDirectory.create("preview") }
        let url = URL(filePath: out, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func write(
        _ frames: [PreviewFrame], report: PreviewReport, to directory: URL
    ) throws {
        let target = report.target
        print("[INFO] target: \(target.kind) \(target.recordType ?? "") "
            + "\(target.editorID ?? "") \(target.formID ?? "") \(target.plugin ?? "") "
            + "model \(target.modelPath ?? "none") cell \(target.cell ?? "none"), "
            + "stage \(report.stage)")
        for failure in report.views.first?.failures ?? [] {
            print("[WARNING] unresolved: \(failure)")
        }
        for (frame, view) in zip(frames, report.views) {
            try FrameScreenshot.write(
                texture: frame.texture, to: directory.appending(path: view.image)
            )
            try PreviewReport.json(view).write(to: directory.appending(path: "\(view.view).json"))
            let coverage = String(format: "%.1f", view.coverage * 100)
            print("[INFO] \(view.view): \(view.drawCalls) draws, \(view.drawnInstances) "
                + "instances, \(view.triangles) triangles, \(coverage)% covered"
                + (view.blank ? " [ERROR] blank" : ""))
        }
        try report.json().write(to: directory.appending(path: "report.json"))
        print("[INFO] wrote \(frames.count) views -> \(directory.path(percentEncoded: false))")
    }
}
