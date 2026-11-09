import OpenSkyFormatsESM
public import OpenSkyGameData

nonisolated extension ActorValueHolder {
    /// The name the readouts show. The NPC_ base FormID is what the user types into the
    /// record dump.
    public var readoutName: String {
        switch subject {
        case .player: "Player"
        case let .actor(base): "\(key.description) (base \(base))"
        case .generated: key.description
        }
    }
}
