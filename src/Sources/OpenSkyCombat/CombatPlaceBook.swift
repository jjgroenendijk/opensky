// The places around one target: the arcs its fighters booked, so two of them do not
// stand in one place. See docs/engine/combat-movement.md#places-around-the-target.

import Foundation
import OpenSkyCombatInterface
import OpenSkyFormatsESM

nonisolated struct CombatPlaceBook: Equatable, Sendable {
    /// One booked arc, by its centre bearing from the target and half its width, in radians.
    struct Arc: Equatable, Sendable {
        var centre: Float
        var halfWidth: Float
    }

    /// The bearings a free place is looked for at, nearest the fighter's own first.
    static let bearingTries = 24
    /// A fighter is out of position past this share of its arc's half width.
    static let holdShare: Float = 0.67
    static let widthLimits: ClosedRange<Float> = 10 * .pi / 180 ... .pi

    private(set) var arcs: [ReferenceKey: Arc] = [:]

    /// Half the arc a fighter of `radius` books at `distance` from its target:
    /// `max(2 * radius * 1.25, width * 2) / distance`, held between 10 and 180 degrees.
    static func halfWidth(radius: Float, distance: Float) -> Float {
        let radius = max(radius, 16)
        let width = max(2 * radius, 32)
        let arc = max(2 * radius * 1.25, width * 2) / max(distance, 1)
        return min(max(arc, widthLimits.lowerBound), widthLimits.upperBound) / 2
    }

    /// The arc overlaps no arc of another fighter.
    func fits(_ arc: Arc, for owner: ReferenceKey) -> Bool {
        arcs.allSatisfy { key, other in
            key == owner || abs(Self.turn(arc.centre - other.centre)) >= arc.halfWidth + other
                .halfWidth
        }
    }

    /// Books `arc` for `owner` in place of its old one. False when it does not fit.
    @discardableResult
    mutating func book(_ arc: Arc, for owner: ReferenceKey) -> Bool {
        guard fits(arc, for: owner) else { return false }
        arcs[owner] = arc
        return true
    }

    /// Frees the arcs of every fighter `keeps` rejects.
    mutating func keep(where keeps: (ReferenceKey) -> Bool) {
        arcs = arcs.filter { keeps($0.key) }
    }

    /// The free bearing nearest `bearing` where an arc of `halfWidth` fits, or nil when the
    /// circle is full.
    func freeBearing(
        near bearing: Float, halfWidth: Float, for owner: ReferenceKey
    ) -> Float? {
        let step = 2 * Float.pi / Float(Self.bearingTries)
        for index in 0 ..< Self.bearingTries {
            let side: Float = index.isMultiple(of: 2) ? 1 : -1
            let candidate = Self.turn(bearing + side * Float((index + 1) / 2) * step)
            if fits(Arc(centre: candidate, halfWidth: halfWidth), for: owner) {
                return candidate
            }
        }
        return nil
    }

    /// The fighter holds no arc, or stands further off its centre than the hold share.
    func isOutOfPosition(_ owner: ReferenceKey, bearing: Float) -> Bool {
        guard let arc = arcs[owner] else { return true }
        return abs(Self.turn(bearing - arc.centre)) > Self.holdShare * arc.halfWidth
    }

    /// An angle in -pi...pi.
    static func turn(_ angle: Float) -> Float {
        remainder(angle, 2 * .pi)
    }
}

/// What the move loop reads about the fighter's place this step.
nonisolated struct CombatPlaceInputs: Equatable, Sendable {
    /// The fighter's bearing from the target, and half the arc it would book, in radians.
    var bearing: Float
    var halfWidth: Float
    var isOutOfPosition: Bool
    /// An arc at the fighter's own bearing fits.
    var canBookHere: Bool
    /// The free bearing nearest the fighter's own, nil when the circle is full.
    var goalBearing: Float?
}
