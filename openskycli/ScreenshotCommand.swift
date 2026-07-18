// `screenshot`: explicit CLI surface for the shared offscreen World-frame
// capture. `render` remains a compatibility alias over the same command.

enum ScreenshotCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        try RenderCommand.run(context: context, scanner: &scanner)
    }
}
