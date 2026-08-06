// Live-renderer seam for the `World > Player & Locomotion` destination
// (issues #188 and #191). Same shape as the other panel bridges: one Equatable
// snapshot crosses from the engine to the readout, polled at 2 Hz, plus the
// actions the sections can invoke.
//
// The seam was declared with the character-controller bridge (#188) so the
// sprint, sneak and jump bindings that milestone added could not be reachable
// only by an unadvertised keystroke; the gate (#191) grew it into the whole
// destination — the live graph, the motion trace, and the two dev controls —
// without changing that shape.
//
// Documented in docs/engine/behavior-runtime.md.

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

/// One graph variable as the readout lists it: the name the bridge writes, the
/// value the graph currently holds, and whether the graph declared it at all.
/// A name the graph does not declare is listed rather than dropped, because a
/// missing binding is the failure the readout exists to make visible.
nonisolated struct LocomotionVariableSnapshot: Equatable, Sendable {
    let name: String
    /// The live value, formatted by the graph's own type, or nil when the graph
    /// declares no variable of that name.
    let value: String?

    var isBound: Bool {
        value != nil
    }
}

/// What the locomotion readout shows for one refresh.
nonisolated struct PlayerLocomotionSnapshot: Equatable, Sendable {
    /// False when there is no renderer at all (no Metal 4 device). Reported
    /// rather than shown as a row of zeros.
    let rendererAvailable: Bool
    /// True while the camera is in walk or third-person mode. Everything below
    /// only advances there; fly mode freezes the values instead of clearing
    /// them.
    let walkModeActive: Bool
    let status: LocomotionStatus
    let bindings: [LocomotionBindingSnapshot]
    /// Resolved gait speeds and their provenance, so the panel can say which
    /// number came from the install and which is an OpenSky fallback.
    let configuration: PlayerMovementConfiguration
    /// The state path the third-person graph resolved on its last update, from
    /// the outermost state machine inward.
    let activeStates: [BehaviorActiveState]
    /// The same for the first-person graph (issue #190), kept apart so a
    /// perspective that diverges is visible rather than averaged.
    let firstPersonActiveStates: [BehaviorActiveState]
    /// Every variable the bridge writes, with the value the graph holds.
    let variables: [LocomotionVariableSnapshot]
    /// The gait held by the dev control, or nil while the player's own input
    /// resolves it.
    let forcedGait: LocomotionGait?
    /// What the third-person graph could not evaluate, which is the honest
    /// coverage number this destination publishes.
    let tally: BehaviorTally?

    static let unavailable = PlayerLocomotionSnapshot(
        rendererAvailable: false,
        walkModeActive: false,
        status: LocomotionStatus(),
        bindings: [],
        configuration: .synthetic,
        activeStates: [],
        firstPersonActiveStates: [],
        variables: [],
        forcedGait: nil,
        tally: nil
    )
}

@MainActor
protocol PlayerLocomotionControlProviding: AnyObject {
    var playerLocomotionSnapshot: PlayerLocomotionSnapshot { get }
    /// Sneak is a toggle, so the panel offers it as one. Sprint and jump are
    /// momentary and are exercised by pressing their keys, which the snapshot
    /// reflects.
    var isSneaking: Bool { get set }
    /// The gait the dev control holds, or nil for ordinary resolution. This is
    /// the destination's one overridden-ness: a forced gait is a setting the
    /// sidebar's reset has to be able to undo, and everything else on the panel
    /// either reads state or acts once.
    var forcedLocomotionGait: LocomotionGait? { get set }
    /// Requests one jump, exactly as the jump key does. Action-only: it leaves
    /// no provider state behind, so it is not an override.
    func requestJump()
    /// Raises one event on the live graph by name, through the same path the
    /// bridge's own edges use. Answers whether the graph declared it.
    @discardableResult
    func raiseLocomotionEvent(named name: String) -> Bool
    /// Empties the root-motion trace and its running totals.
    func clearLocomotionTrace()
}
