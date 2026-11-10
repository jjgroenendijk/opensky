// The scripted-state names that both the natives and the bridge read.

extension PapyrusWorldStateBridge {
    nonisolated static let stolenValueCrimeName = "stolenValueCrime"
    nonisolated static let stolenValueNoCrimeName = "stolenValueNoCrime"
    nonisolated static let ownerSetName = "ownerSet"
    nonisolated static let activationBlockedName = "activationBlocked"
    nonisolated static let ashPileOwnerName = "ashPileOwner"
    /// The flags `SetInChargen` sets, in argument order.
    nonisolated static let chargenFlags = ["chargenNoSaving", "chargenNoWaiting", "chargenMessage"]
    /// OpenSky draws the sun at infinity, so a position is this far from the player along it.
    nonisolated static let sunDistance: Float = 100_000

    nonisolated static func controlDisabledName(_ control: String) -> String {
        "controlDisabled:\(control)"
    }
}
