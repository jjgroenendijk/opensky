// PlaceObject3 filters and blend mode on scene draws, without an offscreen pass: a drop
// shadow or glow draws as tinted copies under the object, a blur as faded copies of it.
// Rules and limits: docs/rendering/swf-layer.md#filters-and-blend-modes.

import Foundation
import simd

/// The filters and blend mode one display object gives the draws of its subtree.
nonisolated struct SWFSceneEffects: Equatable, Sendable {
    var filters: [SWFFilter] = []
    var blendMode: UInt8?

    static let addBlendMode: UInt8 = 8
    /// Copies spread around a blur's radius. More copies draw a smoother edge.
    static let blurCopies = 8
    /// A blur below this many pixels draws one copy.
    static let smallestBlur: Float = 1.5
    /// The most alpha the copies of a blur add up to, so each copy stays see-through.
    static let blurredAlpha: Float = 0.99
    static let twipsPerPixel: Float = 20

    var isEmpty: Bool {
        filters.isEmpty && blendMode != Self.addBlendMode
    }

    mutating func update(from placement: SWFPlacement) {
        filters = placement.filters ?? filters
        blendMode = placement.blendMode ?? blendMode
    }

    /// The commands of one object's subtree, with its effects applied.
    func apply(to commands: [SWFSceneCommand]) -> [SWFSceneCommand] {
        let source = blendMode == Self.addBlendMode ? commands.map(Self.additive) : commands
        var shadows: [SWFSceneCommand] = []
        var blurred = source
        var drawsSource = true
        for filter in filters {
            switch filter {
            case let .shadow(shadow) where !shadow.isInner && !shadow.isKnockout:
                shadows += Self.shadowCopies(of: source, shadow)
                drawsSource = drawsSource && shadow.drawsSource
            case let .blur(x, y):
                blurred = Self
                    .copies(of: blurred, blur: SIMD2(x, y), shift: .zero) { color, alpha in
                        var faded = color
                        faded.multiply.w *= alpha
                        faded.add.w *= alpha
                        return faded
                    }
            default:
                continue
            }
        }
        return drawsSource ? shadows + blurred : shadows
    }

    private static func shadowCopies(
        of commands: [SWFSceneCommand], _ shadow: SWFShadowFilter
    ) -> [SWFSceneCommand] {
        let tint = SIMD3(
            Float(shadow.color.red), Float(shadow.color.green), Float(shadow.color.blue)
        ) / 255
        let opacity = min(1, Float(shadow.color.alpha) / 255 * shadow.strength)
        let shift = SIMD2(cos(shadow.angle), sin(shadow.angle)) * shadow.distance * twipsPerPixel
        let silhouette = { (color: SWFColorTransform, alpha: Float) in
            SWFColorTransform(
                multiply: SIMD4(0, 0, 0, color.multiply.w * opacity * alpha),
                add: SIMD4(tint, color.add.w * opacity * alpha)
            )
        }
        let blur = SIMD2(shadow.blurX, shadow.blurY)
        return copies(of: commands, blur: blur, shift: shift, recolour: silhouette)
    }

    /// Copies of every draw, moved by `shift` twips plus a point on the blur's ring, with
    /// `recolour` given each copy's alpha. Masks stay where they are.
    private static func copies(
        of commands: [SWFSceneCommand],
        blur: SIMD2<Float>,
        shift: SIMD2<Float>,
        recolour: (SWFColorTransform, Float) -> SWFColorTransform
    ) -> [SWFSceneCommand] {
        let ring = max(blur.x, blur.y) < smallestBlur ? [SIMD2<Float>.zero] : (0 ..< blurCopies)
            .map {
                let turn = Float($0) / Float(blurCopies) * 2 * Float.pi
                return SIMD2(cos(turn), sin(turn)) * blur / 2 * twipsPerPixel
            }
        let alpha = ring.count == 1 ? 1 : 1 - pow(1 - blurredAlpha, 1 / Float(ring.count))
        return ring.flatMap { point in
            commands.map { command in
                guard case .draw(var item, let clipCount) = command else { return command }
                item.transform.translateX += shift.x + point.x
                item.transform.translateY += shift.y + point.y
                item.colorTransform = recolour(item.colorTransform, alpha)
                return .draw(item: item, clipCount: clipCount)
            }
        }
    }

    private static func additive(_ command: SWFSceneCommand) -> SWFSceneCommand {
        guard case .draw(var item, let clipCount) = command else { return command }
        item.isAdditive = true
        return .draw(item: item, clipCount: clipCount)
    }
}

nonisolated extension [SWFSceneCommand] {
    /// Applies an object's effects to the commands its subtree added from `start` on.
    mutating func apply(_ effects: SWFSceneEffects, from start: Int) {
        guard !effects.isEmpty, start < count else { return }
        replaceSubrange(start..., with: effects.apply(to: Array(self[start...])))
    }
}

nonisolated extension SWFMovieTally {
    mutating func count(shadows filters: [SWFFilter]) {
        for case let .shadow(shadow) in filters {
            let flags = [
                shadow.isInner ? "inner" : nil, shadow.isKnockout ? "knockout" : nil,
                shadow.drawsSource ? nil : "hides object", shadow.isGlow ? "glow" : "drop shadow"
            ]
            for flag in flags.compactMap(\.self) {
                shadowFlags[flag, default: 0] += 1
            }
            shadowLargest = simd_max(
                shadowLargest, SIMD2(max(shadow.blurX, shadow.blurY), shadow.distance)
            )
        }
    }
}
