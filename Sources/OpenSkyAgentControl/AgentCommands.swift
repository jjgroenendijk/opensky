// The typed commands the router hands the game. Parsing lives here, so a
// malformed argument is caught and tested without the app.

import Foundation

/// A read of game state. Each case answers with one JSON object.
nonisolated public enum AgentStateQuery: Equatable, Sendable {
    case player
    case target
    case actors(radius: Float)
    case menu
    case quest(String)
    case scenes
    /// With a reference, also its script instances and their variables.
    case scripts(reference: String?)
    /// The actor's package, its procedure progress, and its newest move result.
    case packages(reference: String)
    case actorValue(reference: String, name: String)
    case global(String)
    case time
    case frame

    public static let defaultActorRadius: Float = 4096

    public static func parse(_ name: String, _ args: AgentArguments) throws(AgentFailure) -> Self {
        switch name {
        case "player": return .player
        case "target": return .target
        case "actors": return try .actors(radius: args
                .optionalFloat("radius") ?? defaultActorRadius)
        case "menu": return .menu
        case "quest": return try .quest(args.string("id"))
        case "av": return try .actorValue(reference: args.string("ref"), name: args.string("name"))
        case "global": return try .global(args.string("id"))
        case "time": return .time
        case "frame": return .frame
        default:
            guard let query = try inspection(name, args) else {
                throw AgentFailure(.unknownCommand, "unknown state query: \(name)")
            }
            return query
        }
    }

    /// The reads that look inside the scripts, scenes, and packages.
    private static func inspection(
        _ name: String, _ args: AgentArguments
    ) throws(AgentFailure) -> Self? {
        switch name {
        case "scenes": .scenes
        case "scripts": try .scripts(reference: args.optionalString("ref"))
        case "packages": try .packages(reference: args.string("ref"))
        default: nil
        }
    }
}

/// Where a teleport goes.
nonisolated public enum AgentTeleportTarget: Equatable, Sendable {
    /// A cell by editor ID, like the console's `coc`.
    case cell(String)
    /// An exterior cell by grid coordinates.
    case grid(x: Int32, y: Int32)
    /// Next to a placed reference.
    case reference(String)
    /// A world position in game units, in the current worldspace.
    case position(SIMD3<Float>)
}

/// A debug change. Each follows the vanilla console command of the same
/// meaning where one exists.
nonisolated public enum AgentDebugCommand: Equatable, Sendable {
    case teleport(AgentTeleportTarget)
    case setTime(hour: Float)
    case weather(String?)
    case setActorValue(reference: String, name: String, value: Float)
    case modActorValue(reference: String, name: String, delta: Float)
    case addItem(reference: String, item: String, count: Int32)
    case removeItem(reference: String, item: String, count: Int32)
    case setQuestStage(quest: String, stage: Int)
    case kill(String)
    case resurrect(String)
    case overlay(name: String, enabled: Bool)

    public static func parse(_ name: String, _ args: AgentArguments) throws(AgentFailure) -> Self {
        switch name {
        case "teleport": return try .teleport(parseTeleport(args))
        case "time": return try .setTime(hour: parseHour(args))
        case "weather": return try .weather(args.optionalString("id"))
        case "av": return try parseActorValue(args)
        case "item": return try parseItem(args)
        case "quest":
            return try .setQuestStage(quest: args.string("id"), stage: args.int("stage"))
        case "kill": return try .kill(args.string("ref"))
        case "resurrect": return try .resurrect(args.string("ref"))
        case "overlay":
            return try .overlay(name: args.string("name"), enabled: args.bool("on", default: true))
        default: throw AgentFailure(.unknownCommand, "unknown debug command: \(name)")
        }
    }

    private static func parseTeleport(
        _ args: AgentArguments
    ) throws(AgentFailure) -> AgentTeleportTarget {
        if args.has("cell") {
            return try .cell(args.string("cell"))
        }
        if args.has("ref") {
            return try .reference(args.string("ref"))
        }
        if args.has("pos") {
            return try .position(args.vector("pos"))
        }
        if args.has("x") || args.has("y") {
            let x = try args.int("x")
            let y = try args.int("y")
            guard let gridX = Int32(exactly: x), let gridY = Int32(exactly: y) else {
                throw args.invalid("x", "a cell grid number")
            }
            return .grid(x: gridX, y: gridY)
        }
        throw AgentFailure(.invalidArgument, "debug.teleport: give cell, ref, pos, or x and y")
    }

    private static func parseHour(_ args: AgentArguments) throws(AgentFailure) -> Float {
        let hour = try args.float("hour")
        guard (0 ..< 24).contains(hour) else { throw args.invalid("hour", "in [0, 24)") }
        return hour
    }

    private static func parseActorValue(_ args: AgentArguments) throws(AgentFailure) -> Self {
        let reference = try args.optionalString("ref") ?? "player"
        let name = try args.string("name")
        if args.has("mod") {
            return try .modActorValue(reference: reference, name: name, delta: args.float("mod"))
        }
        return try .setActorValue(reference: reference, name: name, value: args.float("value"))
    }

    private static func parseItem(_ args: AgentArguments) throws(AgentFailure) -> Self {
        let reference = try args.optionalString("ref") ?? "player"
        let item = try args.string("id")
        let count = try args.optionalInt("count") ?? 1
        guard let amount = Int32(exactly: count), amount != 0 else {
            throw args.invalid("count", "a non-zero whole number")
        }
        return amount > 0
            ? .addItem(reference: reference, item: item, count: amount)
            : .removeItem(reference: reference, item: item, count: -amount)
    }
}

/// How an input action is applied.
nonisolated public enum AgentInputPhase: String, Sendable {
    /// Held actions go down and stay down; one-shot actions fire once.
    case press
    case release
}

/// By default a screenshot is the next frame the window presents. A size or
/// `worldOnly` needs a second render, so it implies `offscreen`.
nonisolated public struct AgentScreenshotRequest: Equatable, Sendable {
    public var path: String
    public var width: Int?
    public var height: Int?
    public var worldOnly: Bool
    public var offscreen: Bool

    public init(
        path: String, width: Int? = nil, height: Int? = nil, worldOnly: Bool = false,
        offscreen: Bool = false
    ) {
        self.path = path
        self.width = width
        self.height = height
        self.worldOnly = worldOnly
        self.offscreen = offscreen || worldOnly || width != nil || height != nil
    }

    public static func parse(_ args: AgentArguments) throws(AgentFailure) -> Self {
        let path = try args.string("out")
        guard path.hasPrefix("/") else { throw args.invalid("out", "an absolute path") }
        var size: [Int]?
        if let text = try args.optionalString("size") {
            let parts = text.lowercased().split(separator: "x").compactMap { Int($0) }
            guard parts.count == 2, parts.allSatisfy({ (16 ... 8192).contains($0) }) else {
                throw args.invalid("size", "WxH, each 16 to 8192")
            }
            size = parts
        }
        return try Self(
            path: path, width: size?[0], height: size?[1],
            worldOnly: args.bool("worldOnly", default: false),
            offscreen: args.bool("offscreen", default: false)
        )
    }
}
