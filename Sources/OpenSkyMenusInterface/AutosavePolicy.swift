import Foundation
import OpenSkyGameData

nonisolated public enum AutosaveTrigger: String, Equatable, Sendable {
    case rest, wait, travel, pause
}
