// What a world load has done so far: the state and time of each stage. The
// launcher draws it live.

import Foundation
import OpenSkyCells
import OpenSkyWorldInterface

nonisolated extension Duration {
    /// Seconds with two decimals, such as `1.25 s`.
    public var secondsText: String {
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return unsafe String(format: "%.2f s", seconds)
    }
}
