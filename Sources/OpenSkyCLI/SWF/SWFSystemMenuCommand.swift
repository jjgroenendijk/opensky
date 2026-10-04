// `swf system-menu`: brings `interface\quest_journal.swf` up on its System page,
// starts one `SystemPage` state by its constant name, optionally presses accept on
// a list row, and prints every GameDelegate call the movie made. This is how the
// Settings, Controls, and Save pages' host calls were measured.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyMenus

enum SWFSystemMenuCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let state = try scanner.option("--state") ?? "SETTINGS_CATEGORY_STATE"
        let row = try scanner.option("--row").flatMap(Int.init)
        let ticks = try scanner.option("--ticks").flatMap(Int.init) ?? 20
        let focus = try scanner.option("--focus")
        let captures = try scanner.option("--capture")?.split(separator: ",").map(String.init) ?? []
        let then = try scanner.option("--then")?.split(separator: ",").map(String.init) ?? []
        let dumps = try scanner.option("--dump")?.split(separator: ",").map(String.init) ?? []
        try scanner.finish()

        let vfs = context.makeFileSystem()
        let runtime = try SWFMovieRuntime(
            movieScene: SWFMovieLoader(fileSystem: vfs).load(path: SystemMenuMovieBridge.moviePath)
        )
        SystemMenuMovieBridge.prepare(runtime: runtime)
        for name in captures {
            runtime.registerHostFunction(name) { call in
                printArguments(name, call.arguments)
                return .undefined
            }
        }
        runtime.start()
        SystemMenuMovieBridge.activate(runtime: runtime) {}
        tick(runtime, ticks)
        runtime.clearInvokeLog()
        guard
            let value = runtime.runtime.registeredClass(named: "SystemPage")?
                .lookup(state)?.property.value
        else {
            throw CLIError.failure("SystemPage has no constant \(state)")
        }
        runtime.callMovie(
            "StartState", atPath: SystemMenuMovieBridge.systemPagePath, arguments: [value]
        )
        if let focus {
            runtime.focusTarget = runtime.node(
                atPath: "\(SystemMenuMovieBridge.systemPagePath)/\(focus)", from: runtime.root
            )
        }
        tick(runtime, ticks)
        printLog(runtime, stage: "state \(state)")
        if let row {
            runtime.clearInvokeLog()
            pressRow(row, runtime: runtime)
            tick(runtime, ticks)
            printLog(runtime, stage: "row \(row)")
        }
        for (index, step) in then.enumerated() {
            runtime.clearInvokeLog()
            try perform(step, runtime: runtime)
            tick(runtime, ticks)
            printLog(runtime, stage: "step \(index) \(step)")
        }
        for path in dumps {
            printNode(path, runtime: runtime)
        }
    }

    /// A menu key, `state:<CONSTANT>`, `focus:<path>`, or `call:<path>:<method>`.
    private static func perform(_ step: String, runtime: SWFMovieRuntime) throws {
        if step.hasPrefix("state:") {
            let name = String(step.dropFirst(6))
            guard
                let value = runtime.runtime.registeredClass(named: "SystemPage")?
                    .lookup(name)?.property.value
            else { throw CLIError.usage("--then: SystemPage has no constant \(name)") }
            runtime.callMovie(
                "StartState", atPath: SystemMenuMovieBridge.systemPagePath, arguments: [value]
            )
        } else if step.hasPrefix("call:") {
            let parts = step.dropFirst(5).split(separator: ":").map(String.init)
            guard parts.count == 2 else { throw CLIError.usage("--then: call:<path>:<name>") }
            runtime.callMovie(
                parts[1], atPath: "\(SystemMenuMovieBridge.systemPagePath)/\(parts[0])"
            )
        } else if step.hasPrefix("focus:") {
            runtime.focusTarget = runtime.node(
                atPath: "\(SystemMenuMovieBridge.systemPagePath)/\(step.dropFirst(6))",
                from: runtime.root
            )
        } else if let event = menuEvent(step) {
            SystemMenuMovieBridge.handle(event, runtime: runtime)
        } else {
            throw CLIError.usage("--then: unknown step \(step)")
        }
    }

    private static func menuEvent(_ name: String) -> MenuInputEvent? {
        switch name {
        case "up": .move(.up)
        case "down": .move(.down)
        case "left": .move(.left)
        case "right": .move(.right)
        case "accept": .button(.accept)
        case "cancel": .button(.cancel)
        default: nil
        }
    }

    static func tick(_ runtime: SWFMovieRuntime, _ count: Int) {
        for _ in 0 ..< count {
            runtime.advance()
        }
    }

    /// Down presses from the top, then accept, through the focused list.
    private static func pressRow(_ row: Int, runtime: SWFMovieRuntime) {
        for _ in 0 ..< row {
            SystemMenuMovieBridge.handle(.move(.down), runtime: runtime)
        }
        SystemMenuMovieBridge.handle(.button(.accept), runtime: runtime)
    }

    static func printLog(_ runtime: SWFMovieRuntime, stage: String) {
        let log = runtime.invokeLog
        print("[INFO] swf probe \(stage): \(log.entries.count) calls")
        for entry in log.entries {
            print(
                "[INFO]   \(entry.direction.rawValue) \(entry.name)(\(entry.arguments)) "
                    + "-> \(entry.result)\(entry.isHandled ? "" : " [unhandled]")"
            )
        }
        let focus = runtime.focusTarget?.targetPath ?? "none"
        print("[INFO]   focus: \(focus)")
    }

    /// Each argument, and one level into every array element's own properties.
    /// An array prints its elements, so a stepper's option list shows.
    nonisolated static func describeDeep(_ value: AS2Value) -> String {
        guard case let .object(object) = value, object.lookup("0") != nil else {
            return SWFInvokeLog.describe(value)
        }
        let items = object.ownPropertyNames.compactMap { name in Int(name).map { ($0, name) } }
            .sorted { $0.0 < $1.0 }
            .map { SWFInvokeLog.describe(object.lookup($0.1)?.property.value ?? .undefined) }
        return "[\(items.joined(separator: ", "))]"
    }

    nonisolated static func printArguments(_ name: String, _ arguments: [AS2Value]) {
        print("[INFO] swf probe capture \(name): \(arguments.count) arguments")
        for (index, argument) in arguments.enumerated() {
            print("[INFO]   arg \(index) = \(SWFInvokeLog.describe(argument))")
            guard case let .object(array) = argument else { continue }
            for key in array.ownPropertyNames.sorted() {
                let element = array.lookup(key)?.property.value ?? .undefined
                guard case let .object(row) = element else {
                    print("[INFO]     [\(key)] = \(SWFInvokeLog.describe(element))")
                    continue
                }
                if row.lookup("value") == nil {
                    row.assign(.number(0), for: "value")
                }
                let fields = row.ownPropertyNames.sorted().map { field in
                    let value = row.lookup(field)?.property.value ?? .undefined
                    return "\(field)=\(describeDeep(value))"
                }
                print("[INFO]     [\(key)] \(fields.joined(separator: " "))")
            }
        }
    }

    static func printNode(_ path: String, runtime: SWFMovieRuntime) {
        guard let node = runtime.node(atPath: path, from: runtime.root) else {
            print("[INFO] swf probe dump \(path): not found")
            return
        }
        print("[INFO] swf probe dump \(path):")
        for name in node.object.ownPropertyNames.sorted() {
            let value = node.object.lookup(name)?.property.value ?? .undefined
            print("[INFO]   \(name) = \(SWFInvokeLog.describe(value))")
            if name == "EntriesA" || name == "entryList" {
                printArguments("\(path).\(name)", [value])
            }
        }
    }
}
