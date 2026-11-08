import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore

nonisolated public struct PapyrusNativeKey: Equatable, Hashable, Sendable {
    public let scriptName: String
    public let functionName: String

    public init(scriptName: String, functionName: String) {
        self.scriptName = PapyrusName.key(scriptName)
        self.functionName = PapyrusName.key(functionName)
    }

    /// A key from names the caller already folded with `PapyrusName.key`.
    public init(foldedScriptName: String, foldedFunctionName: String) {
        scriptName = foldedScriptName
        functionName = foldedFunctionName
    }
}
