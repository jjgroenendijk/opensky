// A placed object that rides on another, such as a cart tethered to its horse.
// The cell build gives its draw instances their FormID, so they can be drawn at
// the live pose. Not saved: the opening cart ride allows no save.

import Foundation
import OpenSkyFormatsESM

nonisolated public struct ReferenceVehicleLink: WorldStateComponent, Hashable, Sendable {
    public let carrier: ReferenceKey

    public static var componentKind: WorldStateComponentKind {
        .vehicleLink
    }

    public init(carrier: ReferenceKey) {
        self.carrier = carrier
    }
}

nonisolated extension WorldStateComponentKind {
    public static let vehicleLink = Self(rawValue: "vehicleLink", order: 32)
}
