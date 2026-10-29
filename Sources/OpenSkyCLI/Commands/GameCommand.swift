// `openskycli game ...`: drives the running app over its agent control socket
// (docs/tools/agent-control.md). Each call prints one JSON object; `--text`
// prints `path: value` lines instead. Words parse against the running app's own
// command list, so a CLI from another build drives it.

import Foundation
import OpenSkyAgentControl
import OpenSkyCLIArguments

struct GameCommandOptions {
    var socketPath: String
    var text: Bool
    var timeout: Double?
    var recordPath: String?

    /// Seconds a command may wait for its reply when `--timeout` is not given.
    static let defaultTimeout = 60.0
    static let connectTimeout = 5.0

    init(_ arguments: GameOptions) {
        timeout = arguments.replyTimeout
        socketPath = arguments.socket ?? AgentSocketLocation.path()
        text = arguments.text
        recordPath = arguments.record
    }
}

enum GameCommand {
    static func send(arguments: GameArguments.Send) throws {
        let options = GameCommandOptions(arguments.game)
        let session = try? AgentClientSession(
            path: options.socketPath, connectTimeout: GameCommandOptions.connectTimeout
        )
        let commands = session.map(commandList) ?? .builtIn
        if let help = AgentCommandHelp.text(for: arguments.words, commands: commands) {
            print(help)
            return
        }
        try send(arguments.words, options: options, session: session, commands: commands)
    }

    /// The app's own commands; an app older than the `catalog` command answers with
    /// this build's list.
    static func commandList(_ session: AgentClientSession) -> AgentCommandList {
        guard
            let reply = try? session.call("catalog", timeout: GameCommandOptions.connectTimeout),
            let result = reply.result,
            let list = AgentCommandList(json: result)
        else { return .builtIn }
        return list
    }

    static func attach(arguments: GameArguments.Attach) throws {
        let options = GameCommandOptions(arguments.game)
        let session = try connect(options)
        print(output(AgentJSON.object(helloFields(session.hello)), options: options))
    }

    static func connect(_ options: GameCommandOptions) throws -> AgentClientSession {
        do {
            return try AgentClientSession(
                path: options.socketPath,
                connectTimeout: GameCommandOptions.connectTimeout
            )
        } catch {
            throw CLIError.failure("\(error.code.rawValue): \(error.message)")
        }
    }

    static func helloFields(_ hello: AgentHello) -> [String: AgentJSON] {
        [
            "protocolVersion": .init(hello.protocolVersion), "app": .string(hello.app),
            "appVersion": .string(hello.appVersion), "dataRoot": .init(hello.dataRoot),
            "worldReady": .bool(hello.worldReady)
        ]
    }

    static func send(
        _ words: [String],
        options: GameCommandOptions,
        session: AgentClientSession?,
        commands: AgentCommandList
    ) throws {
        var request: AgentRequest
        do {
            request = try AgentCommandLine.request(words, commands: commands)
        } catch {
            var failure = error
            if failure.code == .unknownCommand, let hello = session?.hello {
                failure.message += " (the running app is \(hello.app) \(hello.appVersion))"
            }
            // On stdout, where a script reads the replies, and with the usage exit code.
            print(output(failure, options: options))
            exit(2)
        }
        if request.command == "screenshot" {
            request
                .args["out"] = try .string(GameScreenshotPath
                    .resolve(request.args["out"]?.stringValue))
        }
        let session = try session ?? connect(options)
        let reply: AgentReply
        do {
            reply = try session.call(
                request.command, args: request.args, timeout: timeout(
                    for: request,
                    options: options
                )
            ) { event in
                print(output(event, options: options))
                fflush(stdout)
            }
        } catch {
            throw CLIError.failure("\(error.code.rawValue): \(error.message)")
        }
        if let recordPath = options.recordPath {
            try record(request, to: recordPath)
        }
        print(output(reply, options: options))
        if !reply.ok {
            exit(1)
        }
    }

    /// A waiting command gets its own wait plus a margin.
    static func timeout(for request: AgentRequest, options: GameCommandOptions) -> Double {
        if let timeout = options.timeout {
            return timeout
        }
        if request.command == "events" {
            // A stream with no timeout runs until the user stops it.
            if let wait = request.args["timeout"]?.doubleValue {
                return wait + 10
            }
            if request.args["follow"] != nil || request.args["until"] != nil {
                return 86400
            }
        }
        if request.command == "debug.teleport" {
            return 180
        }
        if request.command == "benchmark" {
            // The full tour takes about half an hour; each scene may wait minutes to arrive.
            return 7200
        }
        return GameCommandOptions.defaultTimeout
    }

    static func output(_ reply: AgentReply, options: GameCommandOptions) -> String {
        guard options.text else { return line(reply) }
        if let error = reply.error {
            return "[ERROR] \(error.code.rawValue): \(error.message)"
        }
        return AgentCommandLine.textLines(reply.result ?? .null).joined(separator: "\n")
    }

    static func output(_ failure: AgentFailure, options: GameCommandOptions) -> String {
        guard options.text else {
            return line(AgentJSON.object([
                "ok": false,
                "error": [
                    "code": .string(failure.code.rawValue),
                    "message": .string(failure.message)
                ]
            ]))
        }
        return "[ERROR] \(failure.code.rawValue): \(failure.message)"
    }

    static func output(_ event: AgentEvent, options: GameCommandOptions) -> String {
        guard options.text else { return line(event) }
        let data = AgentCommandLine.textLines(.object(event.data)).joined(separator: ", ")
        return "event \(event.seq) frame \(event.frame) \(event.kind) \(data)"
    }

    static func output(_ value: AgentJSON, options: GameCommandOptions) -> String {
        options.text ? AgentCommandLine.textLines(value).joined(separator: "\n") : line(value)
    }

    static func line(_ value: some Encodable) -> String {
        AgentLineCodec.text(value)
    }

    private static func record(_ request: AgentRequest, to path: String) throws {
        let url = URL(filePath: path)
        let line = Data(AgentScript.line(for: request).utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
    }
}

/// `screenshot` without `--out` writes to `.logs/game-screenshot/<UTC>/`,
/// the run-directory layout of `tools/run-dir.sh`.
enum GameScreenshotPath {
    static func resolve(_ out: String?) throws -> String {
        let current = URL(
            filePath: FileManager.default.currentDirectoryPath,
            directoryHint: .isDirectory
        )
        if let out {
            return URL(filePath: out, relativeTo: current).standardizedFileURL
                .path(percentEncoded: false)
        }
        let run = try RunDirectory.create("game-screenshot")
        return run.appending(path: "screenshot.png").path(percentEncoded: false)
    }
}
