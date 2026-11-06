// The debug commands that change how an actor or the screen looks.

nonisolated extension AgentDebugCommand {
    /// The commands that change how one actor looks or moves: drunk, eyes, a paired idle.
    static func parseActorLook(
        _ name: String, _ args: AgentArguments
    ) throws(AgentFailure) -> Self {
        switch name {
        case "drunk":
            try .drunk(reference: args.string("ref"), drunk: args.bool("on", default: true))
        case "eyes": try .eyes(reference: args.string("ref"), textureSet: args.string("set"))
        case "paired":
            try .paired(
                reference: args.string("ref"), target: args.string("target"),
                idle: args.string("idle")
            )
        default: try parseScreen(name, args)
        }
    }

    /// The commands that cover the screen: fades, the cart HUD, movies, and titles, and
    /// the sound switch.
    static func parseScreen(
        _ name: String, _ args: AgentArguments
    ) throws(AgentFailure) -> Self {
        switch name {
        case "fade": try parseFade(args)
        case "cartmode": try .cartMode(args.bool("on", default: true))
        case "playbink":
            try .playBink(
                file: args.string("file"), interruptible: args.bool("interruptible", default: false)
            )
        case "skipbink": .skipBink
        case "titles": try .titles(args.string("step"))
        case "sound": try .sound(on: args.bool("on", default: true))
        case "setting":
            try .settings(
                args.optionalString("values")?.split(separator: ",").map(String.init) ?? []
            )
        default: throw AgentFailure(.unknownCommand, "unknown debug command: \(name)")
        }
    }

    static func parseKnock(_ args: AgentArguments) throws(AgentFailure) -> Self {
        let damage = try args.float("damage")
        guard damage.isFinite, damage > 0 else { throw args.invalid("damage", "above 0") }
        return try .knock(reference: args.string("ref"), damage: damage)
    }

    static func parseGamepad(_ args: AgentArguments) throws(AgentFailure) -> Self {
        let count = try args.optionalInt("count")
        if let count, !(0 ... 3).contains(count) {
            throw args.invalid("count", "0 to 3")
        }
        let press = try args.optionalString("press")?.lowercased()
            .split(separator: ",").map(String.init) ?? []
        return .gamepad(count: count, press: press)
    }

    static func parseFade(_ args: AgentArguments) throws(AgentFailure) -> Self {
        let direction = try args.string("direction").lowercased()
        guard direction == "out" || direction == "in" else {
            throw args.invalid("direction", "out or in")
        }
        return try .fade(AgentFadeRequest(
            fadingOut: direction == "out", black: !args.bool("white", default: false),
            delay: args.optionalFloat("delay") ?? 0, duration: args.optionalFloat("duration") ?? 0
        ))
    }
}
