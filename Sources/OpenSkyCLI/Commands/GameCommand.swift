// `openskycli game ...`: drives the running app over its agent control socket
// (docs/tools/agent-control.md). Each call prints one JSON object; `--text`
// prints `path: value` lines instead.

import Foundation
import OpenSkyAgentControl

struct GameCommandOptions {
    var socketPath: String
    var text: Bool
    var timeout: Double?
    var recordPath: String?

    /// Seconds a command may wait for its reply when `--timeout` is not given.
    static let defaultTimeout = 60.0
    static let connectTimeout = 5.0

    static func scan(_ scanner: inout ArgumentScanner) throws -> Self {
        let socket = try scanner.option("--socket")
        let timeout = try scanner.option("--reply-timeout").map { text in
            guard let value = Double(text), value > 0 else {
                throw CLIError.usage("--reply-timeout needs a positive number of seconds")
            }
            return value
        }
        return try GameCommandOptions(
            socketPath: socket ?? AgentSocketLocation.path(),
            text: scanner.flag("--text"),
            timeout: timeout,
            recordPath: scanner.option("--record")
        )
    }
}

enum GameCommand {
    static func run(dataRoot: String?, scanner: inout ArgumentScanner) throws {
        let options = try GameCommandOptions.scan(&scanner)
        var words: [String] = []
        while let word = scanner.next() {
            words.append(word)
        }
        switch words.first {
        case nil:
            throw CLIError.usage("game needs a command, such as status")
        case "launch":
            try GameLaunch.run(Array(words.dropFirst()), dataRoot: dataRoot, options: options)
        case "attach":
            let session = try connect(options)
            print(output(AgentJSON.object(helloFields(session.hello)), options: options))
        case "run":
            try GameScriptRun.run(Array(words.dropFirst()), options: options)
        default:
            try send(words, options: options)
        }
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

    private static func send(_ words: [String], options: GameCommandOptions) throws {
        var request: AgentRequest
        do {
            request = try AgentCommandLine.request(words)
        } catch {
            throw CLIError.usage(error.message)
        }
        if request.command == "screenshot" {
            request
                .args["out"] = try .string(GameScreenshotPath
                    .resolve(request.args["out"]?.stringValue))
        }
        let session = try connect(options)
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
        return GameCommandOptions.defaultTimeout
    }

    static func output(_ reply: AgentReply, options: GameCommandOptions) -> String {
        guard options.text else { return line(reply) }
        if let error = reply.error {
            return "[ERROR] \(error.code.rawValue): \(error.message)"
        }
        return AgentCommandLine.textLines(reply.result ?? .null).joined(separator: "\n")
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

/// `screenshot` without `--out` writes to `logs/game-screenshot/<UTC>/`,
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
        let stamp = Date()
            .formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
                .timeSeparator(.omitted).dateSeparator(.omitted))
        let base = current.appending(path: "logs/game-screenshot")
        let run = base.appending(path: stamp)
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        let latest = base.appending(path: "latest")
        try? FileManager.default.removeItem(at: latest)
        try? FileManager.default.createSymbolicLink(
            atPath: latest.path(percentEncoded: false),
            withDestinationPath: stamp
        )
        return run.appending(path: "screenshot.png").path(percentEncoded: false)
    }
}
