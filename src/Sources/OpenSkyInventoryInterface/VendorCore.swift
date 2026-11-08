import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData

/// Why a vendor is not trading right now.
nonisolated public enum VendorUnavailability: Equatable, Sendable {
    /// Outside the `VENV` hours, or a faction with no hours at all.
    case closed(VendorHours?)
    /// The merchant is not where its `PLVD` rule says it trades.
    case awayFromPlace
    /// A vendor condition failed; the function's name.
    case conditionFailed(String)

    public var text: String {
        switch self {
        case let .closed(hours?) where hours.start != hours.end:
            "closed, open \(hours.start) to \(hours.end)"
        case .closed: "offers no services: no trading hours"
        case .awayFromPlace: "not at the place it trades"
        case let .conditionFailed(function): "vendor condition \(function) fails"
        }
    }
}
