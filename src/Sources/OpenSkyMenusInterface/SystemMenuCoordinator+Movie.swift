import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyRendering

nonisolated public struct SystemMenuMovieDiagnostics: Equatable, Sendable {
    /// `SystemPage.iCurrentState`.
    public let state: Int?
    public let faults: Int
    /// Names the movie looked up and did not find.
    public let missingNames: [String]

    public init(
        state: Int?,
        faults: Int,
        missingNames: [String]
    ) {
        self.state = state
        self.faults = faults
        self.missingNames = missingNames
    }
}
