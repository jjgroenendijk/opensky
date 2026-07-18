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
    static let usage = """
    usage: openskycli [--data-root <path>] <command> [options]

    commands:
      vfs ls [pattern]            List archive entries (fnmatch wildcards or
                                  substring); prints "path<TAB>archive"
      vfs cat <key> --out <file>  Extract one resource to a file
      record <formid-or-editorid> Dump one Skyrim.esm record (decoded + fields)
      cell [--worldspace <edid>] [--x <n>] [--y <n>] [--refs]
                                  Summarize an exterior cell's references
      nif <key>                   Inspect a mesh: container stats, model summary
      dds <key>                   Inspect a texture: header + mip chain
      render --out <file> [--worldspace <edid>] [--x <n>] [--y <n>]
             [--size WxH] [--zoom <f>]
                                  Offscreen-render a cell to a PNG; zoom
                                  moves the eye toward the framed center
      bench [--worldspace <edid>] [--x <n>] [--y <n>] [--size WxH]
            [--frames <n>] [--budget-ms <f>]
                                  Sustained offscreen render; report frame
                                  stats, fail when avg/p95 miss the budget
      help                        Show this text

    defaults: cell/render target the first-render cell (Tamriel (6,-2)).

    options:
      --data-root <path>          Skyrim SE install (or Data/) folder. Default:
                                  OPENSKY_DATA_ROOT env var, OpenSkyDataRoot
                                  user default, then the Steam install path.
    """

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
        switch command {
        case "help", "--help", "-h":
            print(usage)
        case "vfs":
            try VFSCommand.run(context: .resolve(dataRootOverride: dataRoot), scanner: &scanner)
        case "record":
            try RecordCommand.run(
                context: .resolve(dataRootOverride: dataRoot),
                scanner: &scanner
            )
        case "cell":
            try CellCommand.run(context: .resolve(dataRootOverride: dataRoot), scanner: &scanner)
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
        case "render":
            try RenderCommand.run(
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
}

/// Diagnostics go to stderr so stdout stays pipeable data.
func printError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}
