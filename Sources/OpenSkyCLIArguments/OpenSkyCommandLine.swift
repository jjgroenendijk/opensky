// The `openskycli` command line, declared with swift-argument-parser
// (docs/decisions/swift-argument-parser.md). This module only parses; the CLI
// target runs each parsed command. It keeps the nonisolated default because
// the parser's property wrappers do not build in a main-actor module.

import ArgumentParser

/// `--data-root`, accepted before the command name or after it.
public struct GlobalOptions: ParsableArguments, Sendable {
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp(
            "Skyrim SE install (or Data/) folder.",
            discussion: "Default: the OPENSKY_DATA_ROOT environment variable, the "
                + "OpenSkyDataRoot user default, then the Steam install path.",
            valueName: "path"
        )
    )
    public var dataRoot: String?

    public init() {}
}

/// A command the CLI target can run: it reads the data root from here.
public protocol CLICommandArguments: ParsableCommand, Sendable {
    var global: GlobalOptions { get }
}

public struct OpenSkyCommandLine: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "openskycli",
        abstract: "Developer checks that run the engine against your own Skyrim SE install.",
        discussion: "cell, screenshot, and render target the first render cell, "
            + "Tamriel (6,-2), unless --worldspace, --x, and --y say otherwise.",
        subcommands: [
            VFSArguments.self, RecordArguments.self, PluginsArguments.self,
            ESSArguments.self, GMSTArguments.self, ArcheryArguments.self,
            FootstepArguments.self, CellArguments.self, ActorArguments.self,
            ActorValuesArguments.self, CollisionArguments.self, InteriorArguments.self,
            NIFArguments.self, DDSArguments.self, HKXArguments.self, HKTArguments.self,
            EffectsArguments.self, SkeletonArguments.self, AnimationArguments.self,
            LODArguments.self, SWFArguments.self, AudioArguments.self,
            ScreenshotArguments.self, BenchArguments.self,
            LaunchBenchArguments.self, AssetCacheArguments.self, BenchmarkArguments.self,
            GameArguments.self
        ]
    )

    /// Lets the parser accept `--data-root` before the command name.
    @OptionGroup public var global: GlobalOptions

    public init() {}
}

/// What one run of the command line asks for.
public enum CommandLineOutcome {
    /// A command to run.
    case run(any CLICommandArguments)
    /// Help or an error: print `message` and exit with `code`. 2 is a usage error. A
    /// zero code prints to standard output, any other to standard error.
    case exit(code: Int32, message: String)
}

extension OpenSkyCommandLine {
    /// The usage exit code the CLI has always used, instead of the parser's 64.
    public static let usageExitCode: Int32 = 2

    public static func outcome(_ arguments: [String]) -> CommandLineOutcome {
        do {
            var command = try parseAsRoot(arguments)
            if let runnable = command as? any CLICommandArguments {
                return .run(runnable)
            }
            // No command, or a group such as `swf` without one, is a usage error.
            if command is OpenSkyCommandLine || command.isGroup {
                return .exit(code: usageExitCode, message: helpMessage(for: type(of: command)))
            }
            // `help <command>` prints the help itself.
            try command.run()
            return .exit(code: 0, message: "")
        } catch {
            return exit(for: error)
        }
    }

    /// Help for one command, printed after a usage error the command found itself.
    public static func help(for command: any ParsableCommand.Type) -> String {
        // The app's own commands reach a hidden `send`; its parent's help lists them.
        helpMessage(for: command == GameArguments.Send.self ? GameArguments.self : command)
    }

    private static func exit(for error: any Error) -> CommandLineOutcome {
        let code = exitCode(for: error).rawValue
        let message = fullMessage(for: error)
        switch code {
        case 0:
            return .exit(code: 0, message: message)
        case ExitCode.validationFailure.rawValue:
            return .exit(code: usageExitCode, message: message)
        default:
            return .exit(code: 1, message: message)
        }
    }
}

extension ParsableCommand {
    fileprivate var isGroup: Bool {
        !Self.configuration.subcommands.isEmpty
    }
}
