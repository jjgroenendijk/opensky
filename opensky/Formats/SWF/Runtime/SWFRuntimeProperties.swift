// The MovieClip / TextField property surface (milestone 8.3.2 phase 2):
// `_x`, `_y`, `_xscale`, `_yscale`, `_width`, `_height`, `_alpha`, `_visible`,
// `_rotation`, `_name`, `_currentframe`, `_totalframes`, `_target`, and the
// read-only remainder of the numbered property table.
//
// Units are the trap. ActionScript property units are pixels and degrees while
// the display list is twips and matrix terms, so every conversion here goes
// through `twipsPerPixel` (20) rather than being written inline. Getting it
// wrong misplaces everything silently, which is why `SWFRuntimePropertyTests`
// pins each conversion.
//
// `_xscale` and `_yscale` are the lengths of the matrix's basis vectors, not
// its `ScaleX`/`ScaleY` terms: a rotated clip still reports 100% scale.
// `_width` and `_height` are the axis-aligned extent of the transformed
// bounding box, which is why they need `SWFBoundsBox`.

import Foundation

nonisolated extension SWFMovieRuntime {
    /// Twips per pixel (SWF spec chapter 1: a twip is 1/20 of a pixel).
    static let twipsPerPixel: Float = 20

    func displayProperty(
        _ property: AS2DisplayProperty,
        of node: SWFDisplayObject
    ) -> AS2Value {
        geometryProperty(property, of: node)
            ?? identityProperty(property, of: node)
            ?? staticProperty(property)
    }

    /// Position, scale, size, rotation, and the two visibility channels.
    private func geometryProperty(
        _ property: AS2DisplayProperty,
        of node: SWFDisplayObject
    ) -> AS2Value? {
        switch property {
        case .positionX: .number(Double(Float(node.matrix.translateX) / Self.twipsPerPixel))
        case .positionY: .number(Double(Float(node.matrix.translateY) / Self.twipsPerPixel))
        case .scaleX: .number(Double(Self.horizontalScale(node.matrix) * 100))
        case .scaleY: .number(Double(Self.verticalScale(node.matrix) * 100))
        case .width: .number(Double(parentBounds(of: node).width / Self.twipsPerPixel))
        case .height: .number(Double(parentBounds(of: node).height / Self.twipsPerPixel))
        case .rotation: .number(Double(Self.rotationDegrees(node.matrix)))
        case .alpha: .number(Double(node.colorTransform.multiply.w * 100))
        case .visible: .boolean(node.isVisible)
        default: nil
        }
    }

    /// Identity and playhead state.
    private func identityProperty(
        _ property: AS2DisplayProperty,
        of node: SWFDisplayObject
    ) -> AS2Value? {
        switch property {
        case .currentFrame: .integer(max(1, node.currentFrame + 1))
        case .totalFrames, .framesLoaded: .integer(max(1, node.frameCount))
        case .target: .string(node.targetPath)
        case .name: node.name.map(AS2Value.string) ?? .string("")
        default: nil
        }
    }

    /// The properties a runtime with no window, no sound, and no pointer can
    /// still answer honestly. They are answered rather than declined so they do
    /// not crowd the missing-API tally with things that will never be
    /// implemented; the pointer pair becomes real when input arrives.
    private func staticProperty(_ property: AS2DisplayProperty) -> AS2Value {
        switch property {
        case .dropTarget, .url: .string("")
        case .highQuality: .integer(1)
        case .focusRect: .boolean(true)
        case .soundBufferTime: .integer(5)
        case .quality: .string("HIGH")
        case .mouseX, .mouseY: .integer(0)
        default: .undefined
        }
    }

    @discardableResult
    func setDisplayProperty(
        _ property: AS2DisplayProperty,
        of node: SWFDisplayObject,
        to value: AS2Value
    ) -> Bool {
        let number = runtime.coercion.toNumber(value)
        switch property {
        case .positionX:
            node.matrix.translateX = Self.twips(number)
        case .positionY:
            node.matrix.translateY = Self.twips(number)
        case .scaleX:
            Self.setHorizontalScale(&node.matrix, to: Float(number) / 100)
        case .scaleY:
            Self.setVerticalScale(&node.matrix, to: Float(number) / 100)
        case .alpha:
            node.colorTransform.multiply.w = Self.finite(Float(number) / 100)
        case .visible:
            node.isVisible = runtime.coercion.toBoolean(value)
        case .width:
            setExtent(of: node, to: Float(number), horizontal: true)
        case .height:
            setExtent(of: node, to: Float(number), horizontal: false)
        case .rotation:
            Self.setRotation(&node.matrix, degrees: Float(number))
        case .name:
            node.name = runtime.coercion.toString(value)
            node.parent?.bindName(of: node)
        default:
            return false
        }
        markDirty()
        return true
    }

    /// `_width = n` rescales the matrix so the transformed bounding box becomes
    /// `n` pixels wide, which is what Flash does — it does not touch the
    /// artwork.
    private func setExtent(of node: SWFDisplayObject, to pixels: Float, horizontal: Bool) {
        let box = parentBounds(of: node)
        let current = horizontal ? box.width : box.height
        let target = pixels * Self.twipsPerPixel
        guard current > 0, target.isFinite, target >= 0 else {
            return
        }
        let factor = target / current
        if horizontal {
            node.matrix.scaleX *= factor
            node.matrix.rotateSkew0 *= factor
        } else {
            node.matrix.rotateSkew1 *= factor
            node.matrix.scaleY *= factor
        }
    }

    // MARK: - Matrix decomposition

    /// Length of the matrix's x basis vector, signed by `ScaleX`.
    static func horizontalScale(_ matrix: SWFMatrix) -> Float {
        let length = (matrix.scaleX * matrix.scaleX + matrix.rotateSkew0 * matrix.rotateSkew0)
            .squareRoot()
        return matrix.scaleX < 0 ? -length : length
    }

    /// Length of the matrix's y basis vector, signed by `ScaleY`.
    static func verticalScale(_ matrix: SWFMatrix) -> Float {
        let length = (matrix.rotateSkew1 * matrix.rotateSkew1 + matrix.scaleY * matrix.scaleY)
            .squareRoot()
        return matrix.scaleY < 0 ? -length : length
    }

    static func rotationDegrees(_ matrix: SWFMatrix) -> Float {
        guard matrix.scaleX != 0 || matrix.rotateSkew0 != 0 else {
            return 0
        }
        return atan2(matrix.rotateSkew0, matrix.scaleX) * 180 / .pi
    }

    private static func setHorizontalScale(_ matrix: inout SWFMatrix, to scale: Float) {
        let current = horizontalScale(matrix)
        guard scale.isFinite else {
            return
        }
        if abs(current) > .ulpOfOne {
            let factor = scale / current
            matrix.scaleX *= factor
            matrix.rotateSkew0 *= factor
        } else {
            matrix.scaleX = scale
            matrix.rotateSkew0 = 0
        }
    }

    private static func setVerticalScale(_ matrix: inout SWFMatrix, to scale: Float) {
        let current = verticalScale(matrix)
        guard scale.isFinite else {
            return
        }
        if abs(current) > .ulpOfOne {
            let factor = scale / current
            matrix.rotateSkew1 *= factor
            matrix.scaleY *= factor
        } else {
            matrix.scaleY = scale
            matrix.rotateSkew1 = 0
        }
    }

    /// Rebuilds the linear part at `degrees` while preserving both basis
    /// lengths — the decomposition Flash's `_rotation` setter performs.
    private static func setRotation(_ matrix: inout SWFMatrix, degrees: Float) {
        guard degrees.isFinite else {
            return
        }
        let radians = degrees * .pi / 180
        let scaleX = horizontalScale(matrix)
        let scaleY = verticalScale(matrix)
        matrix.scaleX = cos(radians) * scaleX
        matrix.rotateSkew0 = sin(radians) * scaleX
        matrix.rotateSkew1 = -sin(radians) * scaleY
        matrix.scaleY = cos(radians) * scaleY
    }

    /// Pixels to twips, clamped into the `Int32` translation domain so a NaN or
    /// an astronomical assignment cannot trap.
    static func twips(_ pixels: Double) -> Int32 {
        guard pixels.isFinite else {
            return 0
        }
        let scaled = (pixels * Double(twipsPerPixel)).rounded()
        return Int32(max(Double(Int32.min), min(Double(Int32.max), scaled)))
    }

    private static func finite(_ value: Float) -> Float {
        value.isFinite ? value : 0
    }
}
