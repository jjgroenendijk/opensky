// The game's pick among a descriptor's files: one at random, and when that is the file
// the descriptor played last, the next one in the list. The last file is kept per
// descriptor, so every actor that uses it shares it. See docs/formats/sound.md#sndr.

public import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct SoundFilePicker: Sendable {
    private var random: SplitMix64
    private var lastPlayed: [FormID: Int] = [:]

    public init(seed: UInt64 = SplitMix64.increment) {
        random = SplitMix64(seed: seed)
    }

    /// The file to play, or nil for a descriptor without files.
    public mutating func path(for sound: ResolvedSound) -> String? {
        let paths = sound.filePaths
        guard !paths.isEmpty else { return nil }
        let descriptor = sound.descriptor.formID
        let roll = Int(random.next() % UInt64(paths.count))
        let index = Self.index(roll: roll, count: paths.count, last: lastPlayed[descriptor])
        lastPlayed[descriptor] = index
        return paths[index]
    }

    static func index(roll: Int, count: Int, last: Int?) -> Int {
        roll == last ? (roll + 1) % count : roll
    }
}
