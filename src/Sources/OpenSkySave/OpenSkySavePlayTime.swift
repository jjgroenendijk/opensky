// The play time a save slot shows.

import Foundation

nonisolated public enum SavePlayTime {
    /// Hours and minutes, such as `12:05`. Seconds are dropped, not rounded.
    public static func text(seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return unsafe String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
