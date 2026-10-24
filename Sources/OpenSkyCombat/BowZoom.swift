// Eagle Eye's bow zoom as a pure rule. UESP "Skyrim:Archery": with the perk, "pressing
// Block while aiming will zoom in your view", it drains stamina, and it cannot start
// under the Slow Time shout. The clip's `bowZoomStop` ends it. See docs/engine/archery.md.

import Foundation

/// What the zoom reads on one frame.
nonisolated public struct BowZoomInput: Equatable, Sendable {
    public var blockHeld = false
    /// A shot is nocked, drawing, or drawn.
    public var aiming = false
    /// `Mod Bow Zoom` over a base of 1. Below 1 the view narrows; 1 means no perk.
    public var viewShare: Float = 1
    /// The player has stamina left to spend.
    public var hasStamina = true
    /// A Slow Time effect runs.
    public var timeIsSlowed = false

    public init(
        blockHeld: Bool = false, aiming: Bool = false, viewShare: Float = 1,
        hasStamina: Bool = true, timeIsSlowed: Bool = false
    ) {
        self.blockHeld = blockHeld
        self.aiming = aiming
        self.viewShare = viewShare
        self.hasStamina = hasStamina
        self.timeIsSlowed = timeIsSlowed
    }
}

nonisolated public struct BowZoom: Equatable, Sendable {
    public private(set) var isZoomed = false
    /// The share of the view's half-angle tangent while zoomed, else 1.
    public private(set) var viewShare: Float = 1
    /// `bowZoomStop` holds the zoom off until the block key comes up.
    public private(set) var isStopped = false

    public init() {}

    /// Ours: no source gives a smallest share, and 0 would divide the view by zero.
    public static let minimumViewShare: Float = 0.05

    public mutating func update(_ input: BowZoomInput) {
        if !input.blockHeld {
            isStopped = false
        }
        let share = input.viewShare.isFinite ? input.viewShare : 1
        let keeps = isZoomed || !input.timeIsSlowed
        isZoomed = input.blockHeld && input.aiming && share < 1 && input.hasStamina
            && keeps && !isStopped
        viewShare = isZoomed ? max(share, Self.minimumViewShare) : 1
    }

    /// The clip's `bowZoomStop`, after a crossbow bolt leaves.
    public mutating func stop() {
        isStopped = true
        isZoomed = false
        viewShare = 1
    }
}
