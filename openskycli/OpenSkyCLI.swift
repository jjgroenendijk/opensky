// OpenSky CLI (todo 2.9): second product target sharing the engine sources —
// repeatable dev checks from the terminal replacing throwaway probe scripts.
// Reads the user's own install only (read-only external input, AGENTS.md
// Legal & IP); the data root comes from --data-root or the GameDataLocator
// resolution chain. Subcommands + target layout: docs/tools/cli.md.

import Foundation

/// CLI failure modes: `usage` prints the usage text and exits 2; `failure`
/// prints the message and exits 1. Engine errors pass through as exit 1.
enum CLIError: Error {
    case usage(String)
    case failure(String)
}

@main
enum OpenSkyCLI {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch let CLIError.usage(message) {
            printError("[ERROR] \(message)\n\n\(usage)")
            exit(2)
        } catch let CLIError.failure(message) {
            printError("[ERROR] \(message)")
            exit(1)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
            printError("[ERROR] \(message)")
            exit(1)
        }
    }

    private static func run(arguments: [String]) throws {
        var scanner = ArgumentScanner(arguments)
        let dataRoot = try scanner.option("--data-root")
        guard let command = scanner.next() else {
            throw CLIError.usage("no command given")
        }
        if try runEngineCommand(command, dataRoot: dataRoot, scanner: &scanner) {
            return
        }
        switch command {
        case "help", "--help", "-h":
            print(usage)
        case "nif":
            try AssetCommand.runNIF(
                context: .resolve(dataRootOverride: dataRoot),
                scanner: &scanner
            )
        case "dds":
            try AssetCommand.runDDS(
                context: .resolve(dataRootOverride: dataRoot),
                scanner: &scanner
            )
        case "hkx":
            try HKXCommand.run(
                context: .resolve(dataRootOverride: dataRoot),
                scanner: &scanner
            )
        case "skeleton":
            try SkeletonCommand.run(
                context: .resolve(dataRootOverride: dataRoot),
                scanner: &scanner
            )
        case "lod":
            try LODCommand.run(
                context: .resolve(dataRootOverride: dataRoot),
                scanner: &scanner
            )
        case "render":
            try RenderCommand.run(
                context: .resolve(dataRootOverride: dataRoot),
                scanner: &scanner
            )
        case "screenshot":
            try ScreenshotCommand.run(
                context: .resolve(dataRootOverride: dataRoot),
                scanner: &scanner
            )
        case "bench":
            try BenchCommand.run(
                context: .resolve(dataRootOverride: dataRoot),
                scanner: &scanner
            )
        default:
            throw CLIError.usage("unknown command: \(command)")
        }
    }

    private static func runEngineCommand(
        _ command: String,
        dataRoot: String?,
        scanner: inout ArgumentScanner
    ) throws -> Bool {
        switch command {
        case "vfs":
            try VFSCommand.run(
                context: .resolve(dataRootOverride: dataRoot), scanner: &scanner
            )
        case "record":
            try RecordCommand.run(
                context: .resolve(dataRootOverride: dataRoot), scanner: &scanner
            )
        case "footstep":
            try FootstepCommand.run(
                context: .resolve(dataRootOverride: dataRoot), scanner: &scanner
            )
        case "gmst":
            try GMSTCommand.run(
                context: .resolve(dataRootOverride: dataRoot), scanner: &scanner
            )
        case "cell":
            try CellCommand.run(
                context: .resolve(dataRootOverride: dataRoot), scanner: &scanner
            )
        case "actor":
            try ActorCommand.run(
                context: .resolve(dataRootOverride: dataRoot), scanner: &scanner
            )
        case "actor-values":
            try ActorValueCommand.run(
                context: .resolve(dataRootOverride: dataRoot), scanner: &scanner
            )
        default:
            // The scene and media commands, in their own pass: this switch is at
            // the strict cyclomatic-complexity limit, and a new command belongs
            // beside its siblings rather than pushing it over.
            return try runSceneCommand(command, dataRoot: dataRoot, scanner: &scanner)
        }
        return true
    }

    private static func runSceneCommand(
        _ command: String,
        dataRoot: String?,
        scanner: inout ArgumentScanner
    ) throws -> Bool {
        switch command {
        case "collision":
            try CollisionCommand.run(
                context: .resolve(dataRootOverride: dataRoot), scanner: &scanner
            )
        case "interior":
            try InteriorCommand.run(
                context: .resolve(dataRootOverride: dataRoot), scanner: &scanner
            )
        case "animation":
            try AnimationCommand.run(
                context: .resolve(dataRootOverride: dataRoot), scanner: &scanner
            )
        case "swf":
            try SWFCommand.run(
                context: .resolve(dataRootOverride: dataRoot), scanner: &scanner
            )
        case "audio":
            try AudioCommand.run(
                context: .resolve(dataRootOverride: dataRoot), scanner: &scanner
            )
        default:
            return false
        }
        return true
    }
}

/// Diagnostics go to stderr so stdout stays pipeable data.
func printError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}
