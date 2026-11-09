// What the Script adapter parts remember between calls. The owner keeps one and hands it to
// each part that needs it, so no part holds the owner.

public import OpenSkyAIPackages
public import OpenSkyFormatsCore
public import OpenSkyGameData
import OpenSkyScripting
public import OpenSkyWeather

public final class ScriptPartState {
    /// Each model's node origins in model space, keyed by lowercased node name.
    public var modelNodes: AssetLoader<String, [String: PosedBone]>?
    /// Node lookups that wait for their model to load.
    public var nodeWaits: [ModelNodeWait] = []
    public var nextNodeToken = ModelNodeWait.firstToken
    /// `Sound.PlayAndWait` answers the scheduler has not taken yet.
    public var soundWaitAnswers: [UInt64: Bool] = [:]
    public var pathWaits = ScriptPathWaits()
    /// `PathToReference` answers the scheduler has not taken yet.
    public var pathWaitAnswers: [UInt64: Bool] = [:]
    /// The session's weather. The composition root sets it, so the host stays port-only.
    public var weather: () -> WeatherSystem? = { nil }
    /// The bridge `makeBridge` built; the script port shows it only as a port.
    weak var bridge: PapyrusWorldStateBridge?

    public init() {}
}
