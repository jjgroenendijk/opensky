// Every command the app answers, with its positionals and options. The command line
// parses against it, the router rejects arguments it does not list, and `game help`
// prints it, so the three cannot drift apart.

import Foundation

nonisolated public struct AgentCommandSpec: Sendable {
    nonisolated public enum OptionKind: Equatable, Sendable {
        /// `--name <value>`.
        case value(String)
        /// `--name` turns it on; it is off when left out.
        case flag
        /// `--no-name` turns it off; it is on when left out.
        case negatedFlag
        /// `--name` or `--no-name`; left out, the app keeps its current state.
        case toggle
    }

    nonisolated public struct Option: Sendable {
        /// The request key, in camel case. The command line spells it in kebab case.
        public let key: String
        public let kind: OptionKind
        public let help: String
    }

    nonisolated public struct Positional: Sendable {
        public let key: String
        public let optional: Bool
        public let help: String
    }

    /// The protocol name, such as `state.av`.
    public let name: String
    public let summary: String
    public let positionals: [Positional]
    public let options: [Option]

    /// Every request key the command reads.
    public var keys: Set<String> {
        Set(positionals.map(\.key) + options.map(\.key))
    }

    public func option(_ key: String) -> Option? {
        options.first { $0.key == key }
    }
}

nonisolated public enum AgentCommandCatalog {
    public static let all: [AgentCommandSpec] = session + time + input + state + debug

    private static let byName = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    public static func spec(_ name: String) -> AgentCommandSpec? {
        byName[name]
    }

    /// Why the app refuses `request` before running it: an unknown command, or an argument
    /// the command does not read. A misspelled option would otherwise fall back silently.
    public static func refusal(of request: AgentRequest) -> AgentFailure? {
        guard let spec = spec(request.command) else {
            return AgentFailure(.unknownCommand, "unknown command: \(request.command)")
        }
        let unknown = Set(request.args.keys).subtracting(spec.keys).sorted()
        guard let first = unknown.first else { return nil }
        return AgentFailure(.invalidArgument, "\(spec.name): unknown argument \(first)")
    }

    private static let session: [AgentCommandSpec] = [
        command("status", "Running, data root, frame, and paused."),
        command("catalog", "Every command this app answers, with its arguments."),
        command("quit", "Quit the app after the reply."),
        command(
            "screenshot",
            "Save the window's next presented frame, debug view included.",
            options: [
                value("out", "png", "An absolute path. Default: a new .logs/game/ run folder."),
                flag("offscreen", "Render a second frame instead of reading the window."),
                value("size", "WxH", "Render a second frame at this size, 16 to 8192 a side."),
                flag("worldOnly", "Render a second frame without the interface.")
            ]
        ),
        command(
            "events",
            "List the event ring, stream new events, or wait for one kind.",
            options: [
                flag("follow", "Stream events as they happen."),
                value("until", "kind", "Wait for the first event of this kind."),
                value("timeout", "s", "Stop streaming or waiting after this many seconds."),
                value("filter", "kinds", "Only these kinds, comma-separated."),
                value("since", "seq", "Only events after this sequence number.")
            ]
        ),
        command(
            "benchmark",
            "Fly the benchmark tour in the open window; reply when it ends.",
            positionals: [optional("preset", "One of quick, standard, or full.")],
            options: [
                value("scenes", "ids", "Scene ids, comma-separated."),
                value("set", "id=value,...", "Player settings for this run, comma-separated."),
                negatedFlag("overlay", "Hide the benchmark overlay."),
                negatedFlag("loadPasses", "Skip the cold and warm load of the first scene."),
                flag("screenshots", "Save PNGs of the start, middle, and end of each scene."),
                flag("windowed", "Run in a window instead of full screen."),
                value("capture", "scene", "Write a GPU trace of this scene."),
                value("out", "dir", "An absolute folder for the result."),
                flag("stop", "Stop the running tour and keep the scenes measured so far.")
            ]
        )
    ]

    private static let time: [AgentCommandSpec] = [
        command("time.pause", "Pause the simulation."),
        command("time.resume", "Resume the simulation."),
        command(
            "time.step",
            "Pause, then draw this many frames.",
            positionals: [optional("n", "Frames, 1 to 100000. Default: 1.")],
            options: [value("seconds", "s", "Seconds per frame, up to 0.1. Default: 1/60.")]
        ),
        command(
            "time.scale",
            "Run the clock this many times faster.",
            positionals: [required("x", "0 to 16.")]
        )
    ]

    private static let input: [AgentCommandSpec] = [
        command(
            "input.press", "Press an action.", positionals: [required("action", actionHelp)]
        ),
        command(
            "input.release", "Release a held action.",
            positionals: [required("action", actionHelp)]
        ),
        command(
            "input.hold",
            "Hold an action for some frames or seconds, then release it.",
            positionals: [required("action", actionHelp)],
            options: [
                value("frames", "n", "Frames to hold, 1 to 100000."),
                value("seconds", "s", "Seconds to hold, up to 600.")
            ]
        ),
        command(
            "input.look",
            "Turn the camera.",
            options: [
                value("dx", "deg", "Degrees to turn right."),
                value("dy", "deg", "Degrees to look up.")
            ]
        ),
        command(
            "input.select",
            "Move the open menu's selection to the row with this label.",
            positionals: [required("label", "The row label, such as a message box button.")]
        ),
        command(
            "input.text", "Type into the open menu that takes text.",
            positionals: [required("text", "The text.")]
        ),
        command(
            "input.point", "Move the cursor over the open menu.", options: viewPoint
        ),
        command("input.click", "Click the open menu.", options: viewPoint)
    ]

    private static let actionHelp = "An action, such as forward, jump, activate, or menuAccept."

    private static let viewPoint = [
        value("x", "0..1", "Fraction of the view width, from the left."),
        value("y", "0..1", "Fraction of the view height, from the top.")
    ]

    static func command(
        _ name: String,
        _ summary: String,
        positionals: [AgentCommandSpec.Positional] = [],
        options: [AgentCommandSpec.Option] = []
    ) -> AgentCommandSpec {
        AgentCommandSpec(name: name, summary: summary, positionals: positionals, options: options)
    }

    static func value(_ key: String, _ valueName: String, _ help: String) -> AgentCommandSpec
        .Option
    {
        .init(key: key, kind: .value(valueName), help: help)
    }

    static func flag(_ key: String, _ help: String) -> AgentCommandSpec.Option {
        .init(key: key, kind: .flag, help: help)
    }

    static func negatedFlag(_ key: String, _ help: String) -> AgentCommandSpec.Option {
        .init(key: key, kind: .negatedFlag, help: help)
    }

    static func toggle(_ key: String, _ help: String) -> AgentCommandSpec.Option {
        .init(key: key, kind: .toggle, help: help)
    }

    static func required(_ key: String, _ help: String) -> AgentCommandSpec.Positional {
        .init(key: key, optional: false, help: help)
    }

    static func optional(_ key: String, _ help: String) -> AgentCommandSpec.Positional {
        .init(key: key, optional: true, help: help)
    }
}
