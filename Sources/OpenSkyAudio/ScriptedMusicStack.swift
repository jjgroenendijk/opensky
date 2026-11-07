// Which scripted music type sounds when scripts added several: the `MUSC` priority
// decides (docs/engine/music.md#scripted-music).

public import OpenSkyFormatsESM

nonisolated public enum ScriptedMusicStack {
    /// A type without `PNAM` ranks as the lowest priority the Creation Kit offers.
    public static let missingPriority = 100

    /// The type with the highest priority (the lowest number); the newest on a tie.
    /// `ids` is in the order scripts added them, newest last.
    public static func top(_ ids: [FormID], priority: (FormID) -> Int?) -> FormID? {
        var best: (id: FormID, priority: Int)?
        for id in ids {
            let rank = priority(id) ?? missingPriority
            if best == nil || rank <= best?.priority ?? .max {
                best = (id, rank)
            }
        }
        return best?.id
    }
}
