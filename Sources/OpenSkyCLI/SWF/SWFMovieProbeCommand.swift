// `swf movie-probe`: starts any interface movie, then runs steps that call movie
// methods with JSON arguments and press keys, and prints every GameDelegate call
// and the nodes asked for. This is how the race menu and map contracts were measured.

import Foundation
import OpenSkyCLIArguments
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyMenus

enum SWFMovieProbeCommand {
    static func run(context: CLIContext, arguments: SWFArguments.MovieProbe) throws {
        let movie = arguments.movie
        guard !movie.isEmpty else { throw CLIError.usage("swf movie-probe needs --movie <path>") }
        let ticks = arguments.ticks
        let captures = arguments.probe.capture?.split(separator: ",").map(String.init) ?? []
        let steps = arguments.probe.then?.split(separator: ";").map(String.init) ?? []
        let dumps = arguments.probe.dump?.split(separator: ",").map(String.init) ?? []

        let vfs = context.makeFileSystem()
        let runtime = try SWFMovieRuntime(movieScene: SWFMovieLoader(fileSystem: vfs)
            .load(path: movie))
        SystemMenuMovieBridge.prepare(runtime: runtime)
        for name in captures {
            runtime.registerHostFunction(name) { call in
                SWFSystemMenuCommand.printArguments(name, call.arguments)
                return .undefined
            }
        }
        runtime.start()
        SWFSystemMenuCommand.tick(runtime, ticks)
        SWFSystemMenuCommand.printLog(runtime, stage: "start")
        for (index, step) in steps.enumerated() {
            runtime.clearInvokeLog()
            try perform(step, runtime: runtime)
            SWFSystemMenuCommand.tick(runtime, ticks)
            SWFSystemMenuCommand.printLog(runtime, stage: "step \(index) \(step)")
        }
        for path in dumps {
            SWFSystemMenuCommand.printNode(path, runtime: runtime)
        }
        print("[INFO] swf probe callbacks: \(runtime.movieCallbackNames.joined(separator: " "))")
        let missing = runtime.tally.missingNames.keys.sorted()
        print("[INFO] swf probe missing: \(missing.joined(separator: " "))")
    }

    /// `call:<path>:<method>[:<JSON array of arguments>]`, `focus:<path>`, or
    /// `key:<Flash key code>`. An
    /// empty path calls a GameDelegate callback.
    private static func perform(_ step: String, runtime: SWFMovieRuntime) throws {
        if step.hasPrefix("focus:") {
            runtime.focusTarget = runtime.node(
                atPath: String(step.dropFirst(6)),
                from: runtime.root
            )
            return
        }
        if step.hasPrefix("key:"), let code = Int(step.dropFirst(4)) {
            runtime.handle(.keyDown(code: code, ascii: 0))
            runtime.handle(.keyUp(code: code))
            return
        }
        let parts = step.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            .map(String.init)
        guard parts.count >= 3, parts[0] == "call" else {
            throw CLIError.usage("swf movie-probe: unknown step \(step)")
        }
        var arguments: [AS2Value] = []
        if parts.count == 4 {
            guard let json = try JSONSerialization.jsonObject(with: Data(parts[3].utf8)) as? [Any]
            else {
                throw CLIError.usage("swf movie-probe: arguments must be a JSON array")
            }
            arguments = json.map { value(from: $0, runtime: runtime) }
        }
        if parts[1].isEmpty {
            runtime.callMovie(parts[2], arguments: arguments)
        } else {
            runtime.callMovie(parts[2], atPath: parts[1], arguments: arguments)
        }
    }

    private static func value(from json: Any, runtime: SWFMovieRuntime) -> AS2Value {
        switch json {
        case let flag as Bool where type(of: json) == type(of: NSNumber(value: true)):
            return .boolean(flag)
        case let number as NSNumber:
            return .number(number.doubleValue)
        case let text as String:
            return .string(text)
        case let list as [Any]:
            return .object(runtime.runtime
                .makeArray(list.map { value(from: $0, runtime: runtime) }))
        case let fields as [String: Any]:
            let object = runtime.runtime.makeObject()
            for (key, field) in fields {
                object.assign(value(from: field, runtime: runtime), for: key)
            }
            return .object(object)
        default:
            return .undefined
        }
    }
}
