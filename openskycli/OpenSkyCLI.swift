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
      help                        Show this text

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
        guard let command = arguments.first else {
            throw CLIError.usage("no command given")
        }
        switch command {
        case "help", "--help", "-h":
            print(usage)
        default:
            throw CLIError.usage("unknown command: \(command)")
        }
    }
}

/// Diagnostics go to stderr so stdout stays pipeable data.
func printError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}
