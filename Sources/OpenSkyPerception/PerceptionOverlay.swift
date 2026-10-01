// The perception pass as overlay primitives: a pure builder, so a test checks
// the primitive list and not pixels. Per observer it draws a view cone on the
// ground, coloured by its strongest state, and a memory line to its investigate
// position. The cone sits slightly above the feet to avoid z-fighting, and the
// pass is depth-tested so a wall hides it. See docs/engine/detection.md.

import Foundation
import OpenSkyDiagnostics
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import simd

nonisolated public enum PerceptionOverlay: Sendable {
    /// Triangles the cone fan is built from. Twenty-four across 180 degrees is
    /// one triangle per 7.5 degrees, which reads as a smooth wedge without
    /// spending the overlay budget on a single actor.
    public static let coneSegmentCount = 24
    /// How far above the feet the fan sits, world units.
    public static let coneHeight: Float = 4
    /// Colours per state, alpha-blended over the world. Unaware is a dim grey
    /// so a room full of idle actors does not wash the scene out.
    public static let unawareColor = SIMD4<Float>(0.55, 0.55, 0.6, 0.10)
    public static let suspiciousColor = SIMD4<Float>(0.95, 0.75, 0.2, 0.18)
    public static let detectedColor = SIMD4<Float>(0.9, 0.2, 0.2, 0.26)
    /// The memory line's colour, opaque so it reads against its own cone.
    public static let memoryColor = SIMD4<Float>(1, 1, 1, 0.9)

    public static func color(for state: DetectionState) -> SIMD4<Float> {
        switch state {
        case .unaware: unawareColor
        case .suspicious: suspiciousColor
        case .detected: detectedColor
        }
    }

    /// Appends one observer's cone and memory line. `state` is the strongest regard
    /// the observer holds about anything; `settings` gives the cone's angle and range.
    public static func append(
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
    public func appendWorldOverlay(
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
