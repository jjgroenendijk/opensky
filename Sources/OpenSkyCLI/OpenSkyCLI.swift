// OpenSky CLI: second product target sharing the engine sources —
// repeatable dev checks from the terminal replacing throwaway probe scripts.
// Reads the user's own install only (read-only external input, AGENTS.md
// Legal & IP); the data root comes from --data-root or the GameDataLocator
// resolution chain. Subcommands + target layout: docs/tools/cli.md.

import Foundation
import OpenSkyCLIArguments

/// CLI failure modes: `usage` prints the command's help and exits 2; `failure`
/// prints the message and exits 1. Engine errors pass through as exit 1.
enum CLIError: Error {
    case usage(String)
    case failure(String)
}

/// A parsed command this target runs. `CommandRunners.swift` conforms each one.
protocol CLIRunnable {
    func execute() async throws
}

@main
enum OpenSkyCLI {
    static func main() async {
        switch OpenSkyCommandLine.outcome(Array(CommandLine.arguments.dropFirst())) {
        case let .exit(code, message):
            if code != 0 {
                printError(message)
            } else if !message.isEmpty {
                print(message)
            }
            exit(code)
        case let .run(command):
            await run(command)
        }
    }

    private static func run(_ command: any CLICommandArguments) async {
        do {
            guard let runnable = command as? any CLIRunnable else {
                throw CLIError.failure("no runner for \(type(of: command))")
            }
            try await runnable.execute()
        } catch let CLIError.usage(message) {
            let help = OpenSkyCommandLine.help(for: type(of: command))
            printError("[ERROR] \(message)\n\n\(help)")
            exit(OpenSkyCommandLine.usageExitCode)
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
}

/// Diagnostics go to stderr so stdout stays pipeable data.
nonisolated func printError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}
