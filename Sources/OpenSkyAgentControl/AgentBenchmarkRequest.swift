// `game benchmark`: the tour's options as the router hands them to the game.
// The game checks the scene and setting names, because only it knows them.

import Foundation

nonisolated public struct AgentBenchmarkRequest: Equatable, Sendable {
    public var preset: String?
    public var scenes: [String] = []
    public var overlay = true
    /// An absolute folder for `result.json`; nil uses the app's Benchmarks folder.
    public var out: String?
    public var capture: String?
    /// `id=value` pairs, as `openskycli benchmark --set` takes them.
    public var settings: [String] = []
    public var loadPasses = true
    public var screenshots = false
    public var fullScreen = true
    /// Ends the running tour instead of starting one.
    public var stop = false

    public init() {}

    public static func parse(_ args: AgentArguments) throws(AgentFailure) -> Self {
        var request = Self()
        request.preset = try args.optionalString("preset")
        request.scenes = try list(args.optionalString("scenes"))
        request.overlay = try args.bool("overlay", default: true)
        request.out = try args.optionalString("out")
        if let out = request.out, !out.hasPrefix("/") {
            throw args.invalid("out", "an absolute path")
        }
        request.capture = try args.optionalString("capture")
        request.settings = try list(args.optionalString("set"))
        request.loadPasses = try args.bool("loadPasses", default: true)
        request.screenshots = try args.bool("screenshots", default: false)
        request.fullScreen = try !args.bool("windowed", default: false)
        request.stop = try args.bool("stop", default: false)
        return request
    }

    private static func list(_ text: String?) -> [String] {
        (text ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
