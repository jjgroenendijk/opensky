// `debug.view`: puts the player at a whole view in one command, such as the Windows
// reference game's view (docs/tools/reference-game.md).

nonisolated public struct AgentViewTarget: Equatable, Sendable {
    public var feet: SIMD3<Float>
    /// OpenSky's angles: yaw 0 looks along +X and turns towards +Y; pitch up is positive.
    public var yawDegrees: Float
    public var pitchDegrees: Float
    /// The exterior worldspace's editor ID; nil keeps the current one.
    public var worldspace: String?
    /// The interior cell's FormID; nil for an exterior.
    public var interiorCell: UInt32?
    public var hour: Float?
    public var weather: UInt32?

    public init(
        feet: SIMD3<Float>, yawDegrees: Float, pitchDegrees: Float, worldspace: String?,
        interiorCell: UInt32?, hour: Float?, weather: UInt32?
    ) {
        self.feet = feet
        self.yawDegrees = yawDegrees
        self.pitchDegrees = pitchDegrees
        self.worldspace = worldspace
        self.interiorCell = interiorCell
        self.hour = hour
        self.weather = weather
    }

    /// The arguments `parse` reads, for a client that sends the command.
    public var arguments: [String: AgentJSON] {
        var values: [String: AgentJSON] = [
            "pos": .init(feet),
            "yaw": .init(yawDegrees),
            "pitch": .init(pitchDegrees)
        ]
        values["worldspace"] = worldspace.map(AgentJSON.string)
        values["interior"] = interiorCell.map(AgentJSON.formID)
        values["hour"] = hour.map(AgentJSON.init)
        values["weather"] = weather.map(AgentJSON.formID)
        return values
    }

    static func parse(_ args: AgentArguments) throws(AgentFailure) -> Self {
        let hour = try args.optionalFloat("hour")
        if let hour, !(0 ..< 24).contains(hour) {
            throw args.invalid("hour", "in [0, 24)")
        }
        return try Self(
            feet: args.vector("pos"), yawDegrees: args.float("yaw"),
            pitchDegrees: args.optionalFloat("pitch") ?? 0,
            worldspace: args.optionalString("worldspace"),
            interiorCell: formID(args, "interior"), hour: hour, weather: formID(args, "weather")
        )
    }

    private static func formID(
        _ args: AgentArguments, _ name: String
    ) throws(AgentFailure) -> UInt32? {
        guard let text = try args.optionalString(name) else { return nil }
        let digits = text.lowercased().hasPrefix("0x") ? String(text.dropFirst(2)) : text
        guard let value = UInt32(digits, radix: 16) else {
            throw args.invalid(name, "a hexadecimal FormID")
        }
        return value
    }
}
