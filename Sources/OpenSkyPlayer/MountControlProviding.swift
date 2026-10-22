// The panel seam of riding: World > Player & Locomotion > Mount (docs/engine/riding.md).

import Foundation
import OpenSkyFormatsESM

@MainActor
public protocol MountControlProviding: AnyObject {
    var mountSnapshot: MountControlSnapshot { get }
    /// Mounts the nearest actor the player can mount.
    func mountNearest()
    func dismountPlayer()
}

/// The mount readout with the actors' names resolved.
nonisolated public struct MountControlSnapshot: Equatable, Sendable {
    public let readout: MountReadout
    public let names: [ReferenceKey: String]

    public init(readout: MountReadout, names: [ReferenceKey: String]) {
        self.readout = readout
        self.names = names
    }

    public var text: String {
        let readout = readout
        let state = switch readout.phase {
        case .none: "on foot"
        case .mounting: "mounting"
        case .riding: readout.isSprinting ? "riding, sprinting" : "riding"
        case .dismounting: "dismounting"
        }
        return [
            "Mount: \(name(readout.mount)) (\(readout.kind?.rawValue ?? "none"))",
            "State: \(state)",
            String(format: "Speed: %.0f", readout.speed),
            "Nearest mountable: \(name(readout.nearest))",
            "Last mount: \(name(readout.lastMount))",
            "Last refusal: \(readout.lastRefusal?.rawValue ?? "none")"
        ].joined(separator: "\n")
    }

    private func name(_ key: ReferenceKey?) -> String {
        guard let key else { return "none" }
        return names[key] ?? key.description
    }
}
