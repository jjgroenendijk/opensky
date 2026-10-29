// `openskycli game launch` and `game run`: the two game commands that span
// more than one request.

import Foundation
import OpenSkyAgentControl
import OpenSkyCLIArguments

enum GameLaunch {
    static let retrySeconds = 0.5

    static func run(arguments: GameArguments.Launch) throws {
        let options = GameCommandOptions(arguments.game)
        let wait = arguments.wait
        // An app already serving the socket is attached to, not launched twice.
        if (try? AgentClientSession(path: options.socketPath, connectTimeout: 2)) == nil {
            try open(
                app: locateApp(arguments.app),
                arguments: arguments,
                socket: options.socketPath
            )
        }
        let status = try waitForWorld(options, seconds: wait, onTitle: arguments.title)
        print(GameCommand.output(status, options: options))
    }

    /// `--app`, then the app this binary is installed in, then the app built beside it,
    /// then `/Applications`.
    static func locateApp(_ path: String?) throws -> URL {
        if let path {
            return URL(filePath: path)
        }
        let binary = URL(filePath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundle = binary.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        if bundle.pathExtension == "app" {
            return bundle
        }
        let sibling = binary.deletingLastPathComponent().appending(path: "OpenSky.app")
        if FileManager.default.fileExists(atPath: sibling.path(percentEncoded: false)) {
            return sibling
        }
        let installed = URL(filePath: "/Applications/OpenSky.app")
        guard FileManager.default.fileExists(atPath: installed.path(percentEncoded: false)) else {
            throw CLIError.failure("no OpenSky.app found; build it or pass --app")
        }
        return installed
    }

    private static func open(
        app: URL, arguments launch: GameArguments.Launch, socket: String
    ) throws {
        var arguments = [
            "-n", app.path(percentEncoded: false),
            "--env", "OPENSKY_AGENT_CONTROL=1",
            "--env", "OPENSKY_SKIP_LAUNCHER=1",
            "--env", "OPENSKY_START_AT_TITLE=\(launch.title ? 1 : 0)",
            "--env", "OPENSKY_SURVIVAL_MODE=\(launch.survivalMode.rawValue)",
            "--env", "OPENSKY_AGENT_SOCKET=\(socket)"
        ]
        if let dataRoot = launch.global.dataRoot {
            arguments += ["--env", "OPENSKY_DATA_ROOT=\(dataRoot)"]
        }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIError.failure("open failed with status \(process.terminationStatus)")
        }
    }

    /// Retries the connection until the app reports a loaded world, or the main
    /// menu for `onTitle`, because the main menu loads no world.
    private static func waitForWorld(
        _ options: GameCommandOptions,
        seconds: Double,
        onTitle: Bool
    ) throws -> AgentJSON {
        let readyKey = onTitle ? "titleMenuOpen" : "worldReady"
        let deadline = Date().addingTimeInterval(seconds)
        var lastStatus: AgentJSON?
        while Date() < deadline {
            if
                let session = try? AgentClientSession(path: options.socketPath, connectTimeout: 2),
                let reply = try? session.call("status", timeout: 10),
                let result = reply.result
            {
                lastStatus = result
                if result[readyKey]?.boolValue == true {
                    return result
                }
            }
            Thread.sleep(forTimeInterval: retrySeconds)
        }
        let state = lastStatus == nil
            ? "the app never answered" : "the world did not finish loading"
        throw CLIError.failure("timeout: \(state) within \(Int(seconds)) s")
    }
}

enum GameScriptRun {
    static func run(arguments: GameArguments.Run) throws {
        let options = GameCommandOptions(arguments.game)
        let path = arguments.script
        let text = try String(contentsOf: URL(filePath: path), encoding: .utf8)
        let steps: [AgentScriptStep]
        do {
            steps = try AgentScript.parse(text)
        } catch {
            throw CLIError.failure(error.message)
        }
        let session = try GameCommand.connect(options)
        for step in steps {
            try runStep(step, session: session, options: options)
        }
        print(GameCommand.output(["ok": true, "steps": .init(steps.count)], options: options))
    }

    /// Prints the step's reply. Stops the run at a failed reply or a missed expectation.
    private static func runStep(
        _ step: AgentScriptStep,
        session: AgentClientSession,
        options: GameCommandOptions
    ) throws {
        var request = step.request
        if request.command == "screenshot" {
            request
                .args["out"] = try .string(GameScreenshotPath
                    .resolve(request.args["out"]?.stringValue))
        }
        let reply: AgentReply
        do {
            reply = try session.call(
                request.command, args: request.args,
                timeout: GameCommand.timeout(for: request, options: options)
            ) { event in
                print(GameCommand.output(event, options: options))
            }
        } catch {
            throw CLIError
                .failure("line \(step.lineNumber): \(error.code.rawValue): \(error.message)")
        }
        print(GameCommand.output(reply, options: options))
        fflush(stdout)
        if let error = reply.error {
            throw CLIError
                .failure("line \(step.lineNumber): \(error.code.rawValue): \(error.message)")
        }
        let misses = AgentScript.mismatches(of: reply.result, against: step.expect)
        guard misses.isEmpty else {
            throw CLIError.failure("line \(step.lineNumber): \(misses.joined(separator: "; "))")
        }
    }
}
