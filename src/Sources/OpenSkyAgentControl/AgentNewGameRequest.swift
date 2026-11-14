// `debug newgame`: a new game at a chosen place, as the launcher's Play starts it.
// The values stay text here; the game checks them against its data.

/// What a new game at a chosen place starts with.
nonisolated public struct AgentNewGameRequest: Equatable, Sendable {
    /// `cell:EditorID`, `exterior:Worldspace:X:Y`, or `marker:Worldspace:Plugin:ObjectID`.
    public let start: String
    /// The hour of the day; nil keeps the hour a new game starts at.
    public let hour: Float?
    /// A weather editor ID to force; nil leaves the weather to the game.
    public let weather: String?
    /// `not-started`, `helgen-hadvar`, or `helgen-ralof`.
    public let story: String
    /// `none`, or the name of an item preset.
    public let items: String
    public let opensRaceMenu: Bool

    public init(
        start: String, hour: Float? = nil, weather: String? = nil,
        story: String = "not-started", items: String = "none", opensRaceMenu: Bool = true
    ) {
        self.start = start
        self.hour = hour
        self.weather = weather
        self.story = story
        self.items = items
        self.opensRaceMenu = opensRaceMenu
    }

    static func parse(_ args: AgentArguments) throws(AgentFailure) -> Self {
        let hour = try args.optionalFloat("hour")
        if let hour, !(0 ... 24).contains(hour) {
            throw args.invalid("hour", "0 to 24")
        }
        return try AgentNewGameRequest(
            start: args.string("at"),
            hour: hour,
            weather: args.optionalString("weather"),
            story: args.optionalString("story") ?? "not-started",
            items: args.optionalString("items") ?? "none",
            opensRaceMenu: args.bool("racemenu", default: true)
        )
    }

    public var json: AgentJSON {
        [
            "start": .string(start),
            "hour": hour.map { AgentJSON($0) } ?? .null,
            "weather": weather.map { AgentJSON.string($0) } ?? .null,
            "story": .string(story),
            "items": .string(items),
            "raceMenu": .bool(opensRaceMenu)
        ]
    }
}
