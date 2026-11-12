// The MovieClip and TextField property surface. Properties use pixels and
// degrees, the display list twips, so every conversion goes through
// `twipsPerPixel`. `_xscale` is the basis vector length, so a rotated clip
// still reads 100%.

import Foundation

nonisolated extension SWFMovieRuntime {
    /// Twips per pixel (SWF spec chapter 1: a twip is 1/20 of a pixel).
    public static let twipsPerPixel: Float = 20

    public func displayProperty(
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
        case .positionX: .number(Double(node.translation.x / Self.twipsPerPixel))
        case .positionY: .number(Double(node.translation.y / Self.twipsPerPixel))
        case .scaleX: .number(Double(node.basisScale.x * 100))
        case .scaleY: .number(Double(node.basisScale.y * 100))
        case .width: .number(Double(parentBounds(of: node).width / Self.twipsPerPixel))
        case .height: .number(Double(parentBounds(of: node).height / Self.twipsPerPixel))
        case .rotation: .number(Double(node.rotationDegrees))
        case .alpha: .number(Double(node.alpha * 100))
        case .visible: .boolean(node.isVisible)
        case .mouseX: .number(Double(mousePosition(in: node).x))
        case .mouseY: .number(Double(mousePosition(in: node).y))
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

    /// The properties a runtime with no window and no sound can still answer
    /// honestly. They are answered rather than declined so they do not crowd the
    /// missing-API tally with things that will never be implemented.
    private func staticProperty(_ property: AS2DisplayProperty) -> AS2Value {
        switch property {
        case .dropTarget, .url: .string("")
        case .highQuality: .integer(1)
        case .focusRect: .boolean(true)
        case .soundBufferTime: .integer(5)
        case .quality: .string("HIGH")
        default: .undefined
        }
    }

    @discardableResult
    public func setDisplayProperty(
        _ property: AS2DisplayProperty,
        of node: SWFDisplayObject,
        to value: AS2Value
    ) -> Bool {
        let number = runtime.coercion.toNumber(value)
        switch property {
        case .positionX:
            node.moveTo(twipsX: Self.twips(number), twipsY: nil)
        case .positionY:
            node.moveTo(twipsX: nil, twipsY: Self.twips(number))
        case .scaleX:
            node.setBasisScale(Float(number) / 100, horizontal: true)
        case .scaleY:
            node.setBasisScale(Float(number) / 100, horizontal: false)
        case .alpha:
            node.alpha = Self.finite(Float(number) / 100)
        case .visible:
            node.isVisible = runtime.coercion.toBoolean(value)
        case .width:
            setExtent(of: node, to: Float(number), horizontal: true)
        case .height:
            setExtent(of: node, to: Float(number), horizontal: false)
        case .rotation:
            node.setRotation(degrees: Float(number))
        case .name:
            node.name = runtime.coercion.toString(value)
            node.parent?.bindName(of: node)
        default:
            return false
        }
        markDirty()
        return true
    }

    /// `_width = n` on a clip rescales its matrix so the transformed box is `n` pixels
    /// wide. On a text field it sets the unscaled box, as CLIK's `Constraints` expects:
    /// it converts a size to local units for every element but a `TextField`.
    private func setExtent(of node: SWFDisplayObject, to pixels: Float, horizontal: Bool) {
        let target = pixels * Self.twipsPerPixel
        if let field = textField(of: node) {
            guard target.isFinite, target >= 0 else { return }
            node.textBounds = Self.resized(field.bounds, to: target, horizontal: horizontal)
            return
        }
        let box = parentBounds(of: node)
        let current = horizontal ? box.width : box.height
        guard current > 0, target.isFinite, target >= 0 else {
            return
        }
        node.scaleBasis(by: target / current, horizontal: horizontal)
    }

    /// The box with its right or bottom side moved so it is `twips` wide or tall.
    private static func resized(_ box: SWFRect, to twips: Float, horizontal: Bool) -> SWFRect {
        let end = Int32(clamping: Int64(min(twips.rounded(), Float(Int32.max / 2))))
        return horizontal
            ? SWFRect(xMin: box.xMin, xMax: box.xMin &+ end, yMin: box.yMin, yMax: box.yMax)
            : SWFRect(xMin: box.xMin, xMax: box.xMax, yMin: box.yMin, yMax: box.yMin &+ end)
    }

    /// Pixels to twips, clamped into the `Int32` translation domain so a NaN or
    /// an astronomical assignment cannot trap.
    public static func twips(_ pixels: Double) -> Int32 {
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

/// The matrix decomposition Flash's `_xscale`, `_yscale`, and `_rotation` read and write.
nonisolated extension SWFMatrix {
    /// Length of the matrix's x basis vector, signed by `ScaleX`.
    var horizontalScale: Float {
        let length = (scaleX * scaleX + rotateSkew0 * rotateSkew0)
            .squareRoot()
        return scaleX < 0 ? -length : length
    }

    /// Length of the matrix's y basis vector, signed by `ScaleY`.
    var verticalScale: Float {
        let length = (rotateSkew1 * rotateSkew1 + scaleY * scaleY)
            .squareRoot()
        return scaleY < 0 ? -length : length
    }

    var rotationDegrees: Float {
        guard scaleX != 0 || rotateSkew0 != 0 else {
            return 0
        }
        return atan2(rotateSkew0, scaleX) * 180 / .pi
    }

    mutating func setHorizontalScale(_ scale: Float) {
        let current = horizontalScale
        guard scale.isFinite else {
            return
        }
        if abs(current) > .ulpOfOne {
            let factor = scale / current
            scaleX *= factor
            rotateSkew0 *= factor
        } else {
            scaleX = scale
            rotateSkew0 = 0
        }
    }

    mutating func setVerticalScale(_ scale: Float) {
        let current = verticalScale
        guard scale.isFinite else {
            return
        }
        if abs(current) > .ulpOfOne {
            let factor = scale / current
            rotateSkew1 *= factor
            scaleY *= factor
        } else {
            scaleY = scale
            rotateSkew1 = 0
        }
    }

    /// Rebuilds the linear part at `degrees` while preserving both basis
    /// lengths — the decomposition Flash's `_rotation` setter performs.
    mutating func setRotation(degrees: Float) {
        guard degrees.isFinite else {
            return
        }
        let radians = degrees * .pi / 180
        let xLength = horizontalScale
        let yLength = verticalScale
        scaleX = cos(radians) * xLength
        rotateSkew0 = sin(radians) * xLength
        rotateSkew1 = -sin(radians) * yLength
        scaleY = cos(radians) * yLength
    }
}

/// The display properties a node answers from its own matrix and colour transform.
nonisolated extension SWFDisplayObject {
    /// The position in the parent, in twips.
    var translation: SIMD2<Float> {
        SIMD2(Float(matrix.translateX), Float(matrix.translateY))
    }

    /// The lengths of the two basis vectors, each signed by its scale.
    var basisScale: SIMD2<Float> {
        SIMD2(matrix.horizontalScale, matrix.verticalScale)
    }

    var rotationDegrees: Float {
        matrix.rotationDegrees
    }

    var alpha: Float {
        get { colorTransform.multiply.w }
        set { colorTransform.multiply.w = newValue }
    }

    /// Moves the node in its parent. A nil coordinate stays where it is.
    func moveTo(twipsX: Int32?, twipsY: Int32?) {
        if let twipsX {
            matrix.translateX = twipsX
        }
        if let twipsY {
            matrix.translateY = twipsY
        }
    }

    func setBasisScale(_ scale: Float, horizontal: Bool) {
        if horizontal {
            matrix.setHorizontalScale(scale)
        } else {
            matrix.setVerticalScale(scale)
        }
    }

    func setRotation(degrees: Float) {
        matrix.setRotation(degrees: degrees)
    }

    /// Scales one basis vector by `factor`, which stretches the transformed box.
    func scaleBasis(by factor: Float, horizontal: Bool) {
        if horizontal {
            matrix.scaleX *= factor
            matrix.rotateSkew0 *= factor
        } else {
            matrix.rotateSkew1 *= factor
            matrix.scaleY *= factor
        }
    }
}
