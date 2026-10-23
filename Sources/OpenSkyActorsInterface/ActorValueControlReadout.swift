// Actor-value readout lines, formatted in the engine target so a unit test can
// check them without a window. See docs/engine/actor-value-store.md.

import Foundation
import OpenSkyGameData

nonisolated extension ActorValueKind {
    /// The three-letter tag the readout's bar line uses. Spelled out here rather
    /// than derived from `rawValue` so a renamed case cannot silently change a
    /// readout a gate asserts on.
    public var shortLabel: String {
        switch self {
        case .health: "HP"
        case .magicka: "MP"
        case .stamina: "SP"
        }
    }
}
