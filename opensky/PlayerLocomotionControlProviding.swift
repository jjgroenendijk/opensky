// Live-renderer seam for the `World > Player & Locomotion` destination
// (issue #188). Same shape as the other panel bridges: one Equatable snapshot
// crosses from the engine to the readout, polled at 2 Hz, plus the actions the
// section can invoke.
//
// The panel itself lands with the locomotion gate (issue #191). This file is
// the contract it builds against, and it exists here rather than there because
// the app-ui rule is that no gameplay key may be reachable only by an
// unadvertised keystroke: the sprint, sneak, and jump bindings this milestone
// adds have to be inspectable and settable from a control, and that starts with
// the provider being able to report and change them.

import Foundation

/// One key binding as the panel presents it. `label` is what the control shows;
/// `isActive` is whether that input is asserted right now, so a user can press
/// the key and watch the row light up rather than trusting the label.
nonisolated struct LocomotionBindingSnapshot: Equatable, Sendable {
    let id: String
    let label: String
    let key: String
    let isActive: Bool
}

/// What the locomotion readout shows for one refresh.
nonisolated struct PlayerLocomotionSnapshot: Equatable, Sendable {
    /// False when there is no renderer at all (no Metal 4 device). Reported
    /// rather than shown as a row of zeros.
    let rendererAvailable: Bool
    /// True while the camera is in walk mode. Everything below only advances
    /// there; fly mode freezes the values instead of clearing them.
    let walkModeActive: Bool
    let status: LocomotionStatus
    let bindings: [LocomotionBindingSnapshot]
    /// Resolved gait speeds and their provenance, so the panel can say which
    /// number came from the install and which is an OpenSky fallback.
    let configuration: PlayerMovementConfiguration

    static let unavailable = PlayerLocomotionSnapshot(
        rendererAvailable: false,
        walkModeActive: false,
        status: LocomotionStatus(),
        bindings: [],
        configuration: .synthetic
    )
}

@MainActor
protocol PlayerLocomotionControlProviding: AnyObject {
    var playerLocomotionSnapshot: PlayerLocomotionSnapshot { get }
    /// Sneak is a toggle, so the panel offers it as one. Sprint and jump are
    /// momentary and are exercised by pressing their keys, which the snapshot
    /// reflects.
    var isSneaking: Bool { get set }
    /// Requests one jump, exactly as the jump key does. Action-only: it leaves
    /// no provider state behind, so it is not an override.
    func requestJump()
}
