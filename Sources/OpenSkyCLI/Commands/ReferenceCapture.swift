// `reference capture`: one run folder under `.logs/reference/` with both captures, their
// difference, the batch file of the view, and a report (`ReferenceComparisonCapture`).

import Foundation
import OpenSkyAgentControl
import OpenSkyCLIArguments
import OpenSkyPreview
import OpenSkyReference

enum ReferenceCapture {
    static func capture(arguments: ReferenceArguments.Capture) throws {
        let prefix = try ReferenceCommand.readyPrefix()
        let options = GameCommandOptions(arguments.game)
        let frame = ReferenceWindowFrame(
            x: 0, y: 0, width: arguments.window.width, height: arguments.window.height
        )
        let run = try ReferenceComparisonRun(directory: RunDirectory.create("reference"))
        let view = try ReferenceCommand.runningView(options)
        try ReferenceConsoleBatch.write(
            view, toggles: arguments.batch.toggles,
            to: [run.batchFile, prefix.batchFile(named: ReferenceConsoleBatch.defaultName)]
        )
        let report: ReferenceComparisonReport
        do {
            report = try ReferenceComparisonCapture.capture(into: run, view: view, frame: frame) {
                try captureOpenSky(to: $0, frame: frame, options: options)
            }
        } catch let error as ReferenceCaptureError {
            throw CLIError.failure(error.localizedDescription)
        }
        print("[INFO] \(report.summary)")
        print("[INFO] Run folder: \(run.directory.path(percentEncoded: false))")
    }

    private static func captureOpenSky(
        to url: URL, frame: ReferenceWindowFrame, options: GameCommandOptions
    ) throws {
        let session = try GameCommand.connect(options)
        let args: [String: AgentJSON] = [
            "out": .string(url.path(percentEncoded: false)),
            "size": .string("\(frame.width)x\(frame.height)"), "worldOnly": .bool(true)
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
}
