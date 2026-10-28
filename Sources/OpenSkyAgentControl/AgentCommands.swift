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
    /// An actor's seat, or a piece of furniture's markers and who holds them.
    case furniture(reference: String)
    /// Each running object graph, such as a trap's, with its state and bone positions.
    case objects(reference: String?)
    /// Each running effect or armour addon graph, with its actor, state, and last event taken.
    case effects(reference: String?)
    /// The placed meshes that play node controllers; with a reference, its driven nodes.
    case nodes(reference: String?)
    /// Each actor in the air, or one actor's flight, with the player's dragon.
    case flight(reference: String?)
    /// The player's mount: its kind, phase, motion, and a dragon's flight and orders.
    case mount
    /// The newest world-state writes, and whether the streamer is loading or rebuilding.
    case changes(limit: Int)
    case actorValue(reference: String, name: String)
    case global(String)
    case time
    case frame
    /// The view in the values the reference game's console takes.
    case view

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
        case "view": return .view
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
        case "furniture": try .furniture(reference: args.optionalString("ref") ?? "player")
        case "objects": try .objects(reference: args.optionalString("ref"))
        case "effects": try .effects(reference: args.optionalString("ref"))
        case "nodes": try .nodes(reference: args.optionalString("ref"))
        case "changes": try .changes(limit: args.optionalInt("limit") ?? 20)
        case "flight": try .flight(reference: args.optionalString("ref"))
        case "mount": .mount
        default: nil
        }
    }
}

/// What `debug flight` asks of a flying actor.
nonisolated public enum AgentFlightOrder: String, Equatable, Sendable {
    case takeOff = "takeoff"
    case land
    /// Land on the nearest perch.
    case perch
    /// Land at once, as a hasty or a crash landing request does.
    case hasty
    case crash
}

/// Where a teleport goes.
nonisolated public enum AgentTeleportTarget: Equatable, Sendable {
    /// A cell by editor ID, like the console's `coc`.
    case cell(String)
    /// An exterior cell by grid coordinates; a nil worldspace keeps the current one.
    case grid(x: Int32, y: Int32, worldspace: String? = nil)
    /// Next to a placed reference.
    case reference(String)
    /// A world position in game units; a nil worldspace keeps the current one.
    case position(SIMD3<Float>, worldspace: String? = nil)
}

/// `Game.FadeOutGame`'s arguments, in seconds.
nonisolated public struct AgentFadeRequest: Equatable, Sendable {
    public let fadingOut: Bool
    public let black: Bool
    public let delay: Float
    public let duration: Float

    public init(fadingOut: Bool, black: Bool, delay: Float, duration: Float) {
        self.fadingOut = fadingOut
        self.black = black
        self.delay = delay
        self.duration = duration
    }
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
    /// The scene pass's debug channel, such as `wireframe`, or `off`.
    case channel(String)
    /// The sun shadow tier: `off`, `low`, or `high`.
    case shadows(String)
    /// Fades the screen as Papyrus `Game.FadeOutGame` does.
    case fade(AgentFadeRequest)
    /// Puts the HUD into or out of cart mode, as Papyrus `Game.SetHudCartMode` does.
    case cartMode(Bool)
    /// Opens the race menu, as the console's `ShowRaceMenu` does; `limited` is
    /// `Game.ShowLimitedRaceMenu`.
    case raceMenu(limited: Bool)
    /// Opens the skills menu as the Quick Stats key does. `sky` turns the perk sky on
    /// or off; `levels` first earns that many character levels.
    case skillsMenu(sky: Bool?, levels: Int)
    /// Runs the benchmark tour; the reply comes when the tour ends.
    case benchmark(AgentBenchmarkRequest)
    /// Seats the actor in `furniture`, or in the nearest loaded furniture with a free seat.
    case sit(reference: String, furniture: String?)
    /// Gets the actor up from its seat.
    case stand(String)
    /// Passes the hours as the wait menu does; `sleeping` as the rest menu does.
    case passTime(hours: Int, sleeping: Bool)
    /// Forces an actor that flies to take off or to land.
    case flight(reference: String, order: AgentFlightOrder)
    /// Starts or stops an actor's drunk state, as the idles `IdleDrunkStart` and
    /// `IdleDrunkStop` do.
    case drunk(reference: String, drunk: Bool)
    /// Puts the player in a beast form, `werewolf` or `vampirelord`, or ends it with `none`.
    case beastForm(String)
    /// Sends an event to the actor's sub-graphs, as `Actor.PlaySubGraphAnimation` does.
    case subGraphEvent(reference: String, event: String)
    /// Sets a variable on the actor's sub-graphs, as `Actor.SetSubGraphFloatVariable` does.
    case subGraphVariable(reference: String, name: String, value: Float)

    public static func parse(_ name: String, _ args: AgentArguments) throws(AgentFailure) -> Self {
        switch name {
        case "teleport": try .teleport(parseTeleport(args))
        case "time": try .setTime(hour: parseHour(args))
        case "weather": try .weather(args.optionalString("id"))
        case "av": try parseActorValue(args)
        case "item": try parseItem(args)
        case "quest":
            try .setQuestStage(quest: args.string("id"), stage: args.int("stage"))
        case "kill": try .kill(args.string("ref"))
        case "resurrect": try .resurrect(args.string("ref"))
        case "racemenu": try .raceMenu(limited: args.bool("limited", default: false))
        case "skillsmenu": try parseSkillsMenu(args)
        default: try parseFurniture(name, args)
        }
    }

    private static func parseSkillsMenu(_ args: AgentArguments) throws(AgentFailure) -> Self {
        let levels = try args.optionalInt("levelup") ?? 0
        guard (0 ... 10).contains(levels) else { throw args.invalid("levelup", "0 to 10") }
        guard args.has("sky") else { return .skillsMenu(sky: nil, levels: levels) }
        return try .skillsMenu(sky: args.bool("sky", default: true), levels: levels)
    }

    private static func parseFurniture(
        _ name: String, _ args: AgentArguments
    ) throws(AgentFailure) -> Self {
        switch name {
        case "sit":
            return try .sit(
                reference: args.optionalString("ref") ?? "player",
                furniture: args.optionalString("furniture")
            )
        case "stand": return try .stand(args.optionalString("ref") ?? "player")
        case "rest":
            let hours = try args.int("hours")
            guard (1 ... 24).contains(hours) else { throw args.invalid("hours", "1 to 24") }
            return try .passTime(hours: hours, sleeping: args.bool("sleep", default: false))
        case "subgraph": return try parseSubGraph(args)
        default: return try parseRender(name, args)
        }
    }

    private static func parseSubGraph(_ args: AgentArguments) throws(AgentFailure) -> Self {
        let reference = try args.string("ref")
        if let event = try args.optionalString("event") {
            return .subGraphEvent(reference: reference, event: event)
        }
        guard let name = try args.optionalString("var") else {
            throw args.invalid("event", "an event, or --var with --value")
        }
        return try .subGraphVariable(reference: reference, name: name, value: args.float("value"))
    }

    private static func parseRender(
        _ name: String, _ args: AgentArguments
    ) throws(AgentFailure) -> Self {
        switch name {
        case "overlay":
            try .overlay(name: args.string("name"), enabled: args.bool("on", default: true))
        case "channel": try .channel(args.string("mode"))
        case "shadows": try .shadows(args.string("quality"))
        case "fade": try parseFade(args)
        case "cartmode": try .cartMode(args.bool("on", default: true))
        case "flight": try parseFlight(args)
        case "drunk":
            try .drunk(reference: args.string("ref"), drunk: args.bool("on", default: true))
        case "form": try .beastForm(args.string("form").lowercased())
        default: throw AgentFailure(.unknownCommand, "unknown debug command: \(name)")
        }
    }

    private static func parseFade(_ args: AgentArguments) throws(AgentFailure) -> Self {
        let direction = try args.string("direction").lowercased()
        guard direction == "out" || direction == "in" else {
            throw args.invalid("direction", "out or in")
        }
        return try .fade(AgentFadeRequest(
            fadingOut: direction == "out", black: !args.bool("white", default: false),
            delay: args.optionalFloat("delay") ?? 0, duration: args.optionalFloat("duration") ?? 0
        ))
    }

    private static func parseFlight(_ args: AgentArguments) throws(AgentFailure) -> Self {
        guard let order = try AgentFlightOrder(rawValue: args.string("order").lowercased()) else {
            throw args.invalid("order", "takeoff, land, perch, hasty, or crash")
        }
        return try .flight(reference: args.string("ref"), order: order)
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
        let worldspace = try args.optionalString("worldspace")
        if args.has("pos") {
            return try .position(args.vector("pos"), worldspace: worldspace)
        }
        if args.has("x") || args.has("y") {
            let x = try args.int("x")
            let y = try args.int("y")
            guard let gridX = Int32(exactly: x), let gridY = Int32(exactly: y) else {
                throw args.invalid("x", "a cell grid number")
            }
            return .grid(x: gridX, y: gridY, worldspace: worldspace)
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
