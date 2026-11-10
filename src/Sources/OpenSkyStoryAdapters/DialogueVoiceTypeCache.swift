public import OpenSkyFormatsESM
public import OpenSkyGameData

/// `VTCK` by actor base, which the speakers part fills. A template walk per actor per
/// condition context costs too much.
public final class DialogueVoiceTypeCache {
    public var byRoll: [LeveledActorRollKey: FormID?] = [:]

    init() {}
}
