// `reference capture`: one run folder with both captures at one size, their difference,
// the batch file of the view, and a report. Captures show game assets, so they stay
// in `.logs/` (root AGENTS.md, Legal & IP boundary).

import CoreGraphics
import Foundation
import OpenSkyAgentControl
import OpenSkyCLIArguments
import OpenSkyReference
import OpenSkyRenderResources

enum ReferenceCapture {
    static func capture(arguments: ReferenceArguments.Capture) throws {
        let prefix = try ReferenceCommand.readyPrefix()
        let options = GameCommandOptions(arguments.game)
        let size = (width: arguments.window.width, height: arguments.window.height)
        let run = try ReferenceComparisonRun(directory: RunDirectory.create("reference"))
        let view = try ReferenceCommand.runningView(options)
        try ReferenceConsoleBatch.write(
            view, toggles: arguments.batch.toggles,
            to: [run.batchFile, prefix.batchFile(named: ReferenceConsoleBatch.defaultName)]
        )
        try captureOpenSky(to: run.openskyImage, size: size, options: options)
        let raw = run.directory.appending(path: "reference-window.png")
        try captureReferenceWindow(to: raw)
        let reference = try TexturePixels(contentsOf: raw, size: size)
        try? FileManager.default.removeItem(at: raw)
        let opensky = try TexturePixels(contentsOf: run.openskyImage, size: size)
        try write(reference, to: run.referenceImage)
        let difference = try TextureImageDifference.compare(
            reference: reference, candidate: opensky, normals: false
        )
        try write(
            TexturePixels.difference(reference: reference, candidate: opensky),
            to: run.differenceImage
        )
        let report = ReferenceComparisonReport(
            view: view, width: size.width, height: size.height,
            rgbPSNR: difference.rgbPSNR, maxChannelError: difference.maxChannelError
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: run.report)
        ReferenceSettings.storeLatestRun(run.directory)
        print("[INFO] \(report.summary)")
        print("[INFO] Run folder: \(run.directory.path(percentEncoded: false))")
    }

    private static func captureOpenSky(
        to url: URL, size: (width: Int, height: Int), options: GameCommandOptions
    ) throws {
        let session = try GameCommand.connect(options)
        let args: [String: AgentJSON] = [
            "out": .string(url.path(percentEncoded: false)),
            "size": .string("\(size.width)x\(size.height)"), "worldOnly": .bool(true)
        ]
        let reply: AgentReply
        do {
            reply = try session.call("screenshot", args: args, timeout: options.timeout ?? 60)
        } catch {
            throw CLIError.failure("\(error.code.rawValue): \(error.message)")
        }
        guard reply.ok else {
            throw CLIError.failure(reply.error?.message ?? "the OpenSky screenshot failed")
        }
    }

    /// `screencapture -l` takes one window without its shadow, even when it is behind another.
    private static func captureReferenceWindow(to url: URL) throws {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0)
            as? [[String: Any]] ?? []
        let windows = info.compactMap { entry -> ReferenceWindowInfo? in
            guard
                let id = entry[kCGWindowNumber as String] as? UInt32,
                let owner = entry[kCGWindowOwnerName as String] as? String,
                let layer = entry[kCGWindowLayer as String] as? Int,
                let bounds = entry[kCGWindowBounds as String] as? [String: Double]
            else { return nil }
            return ReferenceWindowInfo(
                id: id, ownerName: owner, layer: layer,
                width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0
            )
        }
        guard let window = ReferenceWindow.pick(windows) else {
            throw CLIError.failure("no reference game window is on screen; run make reference-game")
        }
        let tool = Process()
        tool.executableURL = URL(filePath: "/usr/sbin/screencapture")
        tool.arguments = ["-x", "-o", "-l\(window.id)", url.path(percentEncoded: false)]
        try tool.run()
        tool.waitUntilExit()
        guard
            tool.terminationStatus == 0,
            FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else {
            throw CLIError.failure("screencapture could not capture window \(window.id)")
        }
    }

    private static func write(_ pixels: TexturePixels, to url: URL) throws {
        guard let image = pixels.cgImage() else {
            throw CLIError.failure("cannot encode \(url.lastPathComponent)")
        }
        try FrameScreenshot.write(image: image, to: url)
    }
}
