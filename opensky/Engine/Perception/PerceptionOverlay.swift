// The perception pass as world-space evidence (issue #202, roadmap item 16.6),
// drawn through the overlay registry item 16.3 built (issue #422).
//
// A pure builder over values, like the navigation source next to it: it takes a
// roster and a set of pair states and appends primitives. It owns no renderer
// state, so a test asserts on the primitive list rather than on pixels, and the
// same function draws in the app and in an offscreen capture.
//
// ## What is drawn, and why that is the useful picture
//
// Two things per observer. The **view cone** is a flat fan on the ground at the
// observer's feet, spanning the cone's full angle out to the range that
// observer's senses actually reach — so a user can see both where an actor is
// looking and how far. It is coloured by the strongest state that observer
// holds about anything, which is the one number a person watching a stealth
// approach cares about. The **memory line** runs from the observer to its
// investigate position, so "it heard something over there" is visible as a
// thing pointing somewhere rather than as a state name.
//
// The fan is drawn slightly above the feet so it does not z-fight with the
// ground it sits on, and the pass is depth-tested, so a cone genuinely
// disappears behind the wall that blocks it.
//
// Documented in docs/engine/detection.md.

import Foundation
import simd

nonisolated enum PerceptionOverlay {
    /// Triangles the cone fan is built from. Twenty-four across 180 degrees is
    /// one triangle per 7.5 degrees, which reads as a smooth wedge without
    /// spending the overlay budget on a single actor.
    static let coneSegmentCount = 24
    /// How far above the feet the fan sits, world units.
    static let coneHeight: Float = 4
    /// Colours per state, alpha-blended over the world. Unaware is a dim grey
    /// so a room full of idle actors does not wash the scene out.
    static let unawareColor = SIMD4<Float>(0.55, 0.55, 0.6, 0.10)
    static let suspiciousColor = SIMD4<Float>(0.95, 0.75, 0.2, 0.18)
    static let detectedColor = SIMD4<Float>(0.9, 0.2, 0.2, 0.26)
    /// The memory line's colour, opaque so it reads against its own cone.
    static let memoryColor = SIMD4<Float>(1, 1, 1, 0.9)

    static func color(for state: DetectionState) -> SIMD4<Float> {
        switch state {
        case .unaware: unawareColor
        case .suspicious: suspiciousColor
        case .detected: detectedColor
        }
    }

    /// Appends one observer's cone and memory line.
    ///
    /// - Parameters:
    ///   - observer: whose cone to draw.
    ///   - state: the strongest regard this observer holds about anything.
    ///   - investigatePosition: where it would go and look, or nil.
    ///   - settings: supplies the cone's half-angle and range.
    static func append(
        observer: PerceptionObserver,
        state: DetectionState,
        investigatePosition: SIMD3<Float>?,
        settings: DetectionSettings,
        to list: inout WorldOverlayDrawList
    ) {
        let range = DetectionFormula.maximumDistance(
            settings: settings, isExterior: observer.isExterior
        )
        guard range > 0, coneSegmentCount > 0 else { return }
        let half = min(max(settings.viewConeHalfAngleDegrees.value, 0), 180) * .pi / 180
        let apex = observer.feet + SIMD3(0, 0, coneHeight)
        let color = color(for: state)
        let step = 2 * half / Float(coneSegmentCount)
        for segment in 0 ..< coneSegmentCount {
            let first = observer.facing - half + step * Float(segment)
            let second = first + step
            list.addTriangle(
                apex,
                apex + SIMD3(cosf(first), sinf(first), 0) * range,
                apex + SIMD3(cosf(second), sinf(second), 0) * range,
                color: color
            )
        }
        guard let investigatePosition else { return }
        list.addLineSegment(
            apex,
            investigatePosition + SIMD3(0, 0, coneHeight),
            color: memoryColor
        )
    }
}

extension PerceptionRuntime {
    /// Every observer's cone and memory line, in roster order.
    ///
    /// Nothing is appended while the toggle is off, so an unenabled overlay
    /// costs one boolean per frame rather than a build that is thrown away.
    func appendWorldOverlay(
        context: WorldOverlayFrameContext,
        to list: inout WorldOverlayDrawList
    ) {
        guard context.detectionOverlayEnabled else { return }
        for observer in observers {
            var strongest = DetectionState.unaware
            var investigatePosition: SIMD3<Float>?
            for (key, pair) in pairs.sorted(by: { $0.key < $1.key })
                where key.observer == observer.key
            {
                guard pair.state != .unaware else { continue }
                if pair.state == .detected || strongest == .unaware {
                    strongest = pair.state
                    investigatePosition = pair.lastKnownPosition
                }
            }
            PerceptionOverlay.append(
                observer: observer,
                state: strongest,
                investigatePosition: investigatePosition,
                settings: settings,
                to: &list
            )
        }
    }
}
