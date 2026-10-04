// `openskycli game launch` and `game run`: the two game commands that span
// more than one request.

import Foundation
import OpenSkyAgentControl

enum GameLaunch {
    static let defaultWaitSeconds = 180.0
    static let retrySeconds = 0.5
    static let modes = ["play", "developer"]

    static func run(_ words: [String], dataRoot: String?, options: GameCommandOptions) throws {
        var scanner = ArgumentScanner(words)
        let mode = try scanner.option("--mode") ?? "play"
        guard modes.contains(mode) else {
            throw CLIError.usage("--mode must be play or developer")
        }
        let appPath = try scanner.option("--app")
        let wait = try scanner.option("--wait").flatMap(Double.init) ?? defaultWaitSeconds
        let title = scanner.flag("--title")
        try scanner.finish()
        // An app already serving the socket is attached to, not launched twice.
        if (try? AgentClientSession(path: options.socketPath, connectTimeout: 2)) == nil {
            try open(
                app: locateApp(appPath),
                mode: mode,
                title: title,
                dataRoot: dataRoot,
                socket: options.socketPath
            )
        }
        let status = try waitForWorld(options, seconds: wait)
        print(GameCommand.output(status, options: options))
    }

    /// `--app`, then the app built beside this binary, then `/Applications`.
    private static func locateApp(_ path: String?) throws -> URL {
        if let path {
            return URL(filePath: path)
        }
        let binary = URL(filePath: CommandLine.arguments[0]).resolvingSymlinksInPath()
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
        app: URL, mode: String, title: Bool, dataRoot: String?, socket: String
    ) throws {
        var arguments = [
            "-n", app.path(percentEncoded: false),
            "--env", "OPENSKY_AGENT_CONTROL=1",
            "--env", "OPENSKY_LAUNCH_MODE=\(mode)",
            "--env", "OPENSKY_START_AT_TITLE=\(title ? 1 : 0)",
            "--env", "OPENSKY_AGENT_SOCKET=\(socket)"
        ]
        if let dataRoot {
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

    /// Retries the connection until the app reports a loaded world.
    private static func waitForWorld(
        _ options: GameCommandOptions,
        seconds: Double
    ) throws -> AgentJSON {
        let deadline = Date().addingTimeInterval(seconds)
        var lastStatus: AgentJSON?
        while Date() < deadline {
            if
                let session = try? AgentClientSession(path: options.socketPath, connectTimeout: 2),
                let reply = try? session.call("status", timeout: 10),
                let result = reply.result
            {
                lastStatus = result
                if result["worldReady"]?.boolValue == true {
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
    static func run(_ words: [String], options: GameCommandOptions) throws {
        guard words.count == 1, let path = words.first else {
            throw CLIError.usage("game run needs one <script.jsonl>")
        }
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
