// Live-renderer seam for the `World > Player & Locomotion` destination: one
// Equatable snapshot polled at 2 Hz, plus the actions the sections invoke. It
// covers the sprint, sneak, and jump bindings, the live graph, the motion
// trace, and the dev controls. See docs/engine/locomotion-graph.md.

import Foundation
import OpenSkyBehavior
import OpenSkyPhysics

/// One key binding as the panel presents it. `label` is what the control shows;
/// `isActive` is whether that input is asserted right now, so a user can press
/// the key and watch the row light up rather than trusting the label.
nonisolated public struct LocomotionBindingSnapshot: Equatable, Sendable {
    public let label: String
    public let key: String
    public let isActive: Bool

    public init(label: String, key: String, isActive: Bool) {
        self.label = label
        self.key = key
        self.isActive = isActive
    }
}

/// One graph variable as the readout lists it: the name the bridge writes, the
/// value the graph currently holds, and whether the graph declared it at all.
/// A name the graph does not declare is listed rather than dropped, because a
/// missing binding is the failure the readout exists to make visible.
nonisolated public struct LocomotionVariableSnapshot: Equatable, Sendable {
    public let name: String
    /// The live value, formatted by the graph's own type, or nil when the graph
    /// declares no variable of that name.
    public let value: String?

    public init(name: String, value: String?) {
        self.name = name
        self.value = value
    }
}

/// What the locomotion readout shows for one refresh.
nonisolated public struct PlayerLocomotionSnapshot: Equatable, Sendable {
    /// False when there is no renderer at all (no Metal 4 device). Reported
    /// rather than shown as a row of zeros.
    public let rendererAvailable: Bool
    /// True while the camera is in walk or third-person mode. Everything below
    /// only advances there; fly mode freezes the values instead of clearing
    /// them.
    public let walkModeActive: Bool
    public let status: LocomotionStatus
    public let bindings: [LocomotionBindingSnapshot]
    /// Resolved gait speeds and their provenance, so the panel can say which
    /// number came from the install and which is an OpenSky fallback.
    public let configuration: PlayerMovementConfiguration
    /// The state path the third-person graph resolved on its last update, from
    /// the outermost state machine inward.
    public let activeStates: [BehaviorActiveState]
    /// The same for the first-person graph, kept apart so a
    /// perspective that diverges is visible rather than averaged.
    public let firstPersonActiveStates: [BehaviorActiveState]
    /// Every variable the bridge writes, with the value the graph holds.
    public let variables: [LocomotionVariableSnapshot]
    /// The gait held by the dev control, or nil while the player's own input
    /// resolves it.
    public let forcedGait: LocomotionGait?
    /// What the third-person graph could not evaluate, which is the honest
    /// coverage number this destination publishes.
    public let tally: BehaviorTally?
    /// Why the player has no third-person body, or nil when one is attached.
    public let bodyFailureReason: String?

    public static let unavailable = PlayerLocomotionSnapshot(
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

    public init(
        rendererAvailable: Bool,
        walkModeActive: Bool,
        status: LocomotionStatus,
        bindings: [LocomotionBindingSnapshot],
        configuration: PlayerMovementConfiguration,
        activeStates: [BehaviorActiveState],
        firstPersonActiveStates: [BehaviorActiveState],
        variables: [LocomotionVariableSnapshot],
        forcedGait: LocomotionGait?,
        tally: BehaviorTally?,
        bodyFailureReason: String? = nil
    ) {
        self.rendererAvailable = rendererAvailable
        self.walkModeActive = walkModeActive
        self.status = status
        self.bindings = bindings
        self.configuration = configuration
        self.activeStates = activeStates
        self.firstPersonActiveStates = firstPersonActiveStates
        self.variables = variables
        self.forcedGait = forcedGait
        self.tally = tally
        self.bodyFailureReason = bodyFailureReason
    }
}

@MainActor
public protocol PlayerLocomotionControlProviding: AnyObject {
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
