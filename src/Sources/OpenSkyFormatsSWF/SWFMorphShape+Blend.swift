// A morph shape at one placement ratio: every point, colour, width, and matrix
// moves in a straight line from its start value to its end value.

import Foundation

nonisolated extension SWFMorphShapeDefinition {
    /// The shape at `ratio`, where 0 is the start form and 65535 the end form.
    public func shape(atRatio ratio: UInt16, characterId: UInt16) -> SWFShapeDefinition {
        let blend = SWFMorphBlend(weight: Float(ratio) / Float(UInt16.max))
        let edgeBounds = startEdgeBounds.flatMap { start in
            endEdgeBounds.map { blend.rect(start, $0) }
        }
        return SWFShapeDefinition(
            characterId: characterId,
            bounds: blend.rect(startBounds, endBounds),
            edgeBounds: edgeBounds,
            usesFillWindingRule: false,
            fillStyles: zip(startFillStyles, endFillStyles).map(blend.fill),
            lineStyles: zip(startLineStyles, endLineStyles).map(blend.line),
            segments: zip(startSegments, endSegments).map(blend.segment)
        )
    }
}

/// One straight-line blend between two values of the same kind. A pair of
/// different kinds, which a malformed file can hold, keeps the start value.
nonisolated struct SWFMorphBlend {
    let weight: Float

    func twips(_ start: Int32, _ end: Int32) -> Int32 {
        let value = (Float(start) + (Float(end) - Float(start)) * weight).rounded()
        return Int32(clamping: Int64(value))
    }

    func scalar(_ start: Float, _ end: Float) -> Float {
        start + (end - start) * weight
    }

    func byte(_ start: UInt8, _ end: UInt8) -> UInt8 {
        UInt8(clamping: Int(scalar(Float(start), Float(end)).rounded()))
    }

    func rect(_ start: SWFRect, _ end: SWFRect) -> SWFRect {
        SWFRect(
            xMin: twips(start.xMin, end.xMin), xMax: twips(start.xMax, end.xMax),
            yMin: twips(start.yMin, end.yMin), yMax: twips(start.yMax, end.yMax)
        )
    }

    func color(_ start: SWFColor, _ end: SWFColor) -> SWFColor {
        SWFColor(
            red: byte(start.red, end.red), green: byte(start.green, end.green),
            blue: byte(start.blue, end.blue), alpha: byte(start.alpha, end.alpha)
        )
    }

    func matrix(_ start: SWFMatrix, _ end: SWFMatrix) -> SWFMatrix {
        var matrix = SWFMatrix()
        matrix.scaleX = scalar(start.scaleX, end.scaleX)
        matrix.scaleY = scalar(start.scaleY, end.scaleY)
        matrix.rotateSkew0 = scalar(start.rotateSkew0, end.rotateSkew0)
        matrix.rotateSkew1 = scalar(start.rotateSkew1, end.rotateSkew1)
        matrix.translateX = twips(start.translateX, end.translateX)
        matrix.translateY = twips(start.translateY, end.translateY)
        return matrix
    }

    func gradient(_ start: SWFGradient, _ end: SWFGradient) -> SWFGradient {
        let records = zip(start.records, end.records).map { from, to in
            SWFGradientRecord(ratio: byte(from.ratio, to.ratio), color: color(from.color, to.color))
        }
        let focal = start.focalPoint.map { from in end.focalPoint.map { scalar(from, $0) } ?? from }
        return SWFGradient(
            spreadMode: start.spreadMode, interpolationMode: start.interpolationMode,
            records: records, focalPoint: focal
        )
    }

    func fill(_ start: SWFFillStyle, _ end: SWFFillStyle) -> SWFFillStyle {
        switch (start, end) {
        case let (.solid(from), .solid(to)):
            .solid(color(from, to))
        case let (.linearGradient(fromMatrix, from), .linearGradient(toMatrix, to)):
            .linearGradient(matrix: matrix(fromMatrix, toMatrix), gradient: gradient(from, to))
        case let (.radialGradient(fromMatrix, from), .radialGradient(toMatrix, to)):
            .radialGradient(matrix: matrix(fromMatrix, toMatrix), gradient: gradient(from, to))
        case let (.focalRadialGradient(fromMatrix, from), .focalRadialGradient(toMatrix, to)):
            .focalRadialGradient(matrix: matrix(fromMatrix, toMatrix), gradient: gradient(from, to))
        case let (.bitmap(id, fromMatrix, tiled, smoothed), .bitmap(_, toMatrix, _, _)):
            .bitmap(
                characterId: id, matrix: matrix(fromMatrix, toMatrix),
                tiled: tiled, smoothed: smoothed
            )
        default:
            start
        }
    }

    func line(_ start: SWFLineStyle, _ end: SWFLineStyle) -> SWFLineStyle {
        var style = start
        style.width = UInt16(clamping: Int(scalar(Float(start.width), Float(end.width)).rounded()))
        style.color = color(start.color, end.color)
        if let from = start.fill, let to = end.fill {
            style.fill = fill(from, to)
        }
        return style
    }

    /// A straight edge paired with a curve becomes a curve with its control point
    /// at the middle of the line, so both forms have the same kind of edge.
    func segment(_ start: SWFShapeSegment, _ end: SWFShapeSegment) -> SWFShapeSegment {
        var edge = Self.curve(start)
        switch (start.edge, end.edge, edge, Self.curve(end)) {
        case let (.line(fromX, fromY), .line(toX, toY), _, _):
            edge = .line(toX: twips(fromX, toX), toY: twips(fromY, toY))
        case let (_, _, .quadratic(fromCX, fromCY, fromX, fromY), .quadratic(toCX, toCY, toX, toY)):
            edge = .quadratic(
                controlX: twips(fromCX, toCX), controlY: twips(fromCY, toCY),
                toX: twips(fromX, toX), toY: twips(fromY, toY)
            )
        default:
            break
        }
        return SWFShapeSegment(
            fromX: twips(start.fromX, end.fromX), fromY: twips(start.fromY, end.fromY),
            edge: edge, fillStyle0: start.fillStyle0, fillStyle1: start.fillStyle1,
            lineStyle: start.lineStyle
        )
    }

    private static func curve(_ segment: SWFShapeSegment) -> SWFShapeSegment.Edge {
        guard case let .line(toX, toY) = segment.edge else { return segment.edge }
        return .quadratic(
            controlX: Int32((Int64(segment.fromX) + Int64(toX)) / 2),
            controlY: Int32((Int64(segment.fromY) + Int64(toY)) / 2),
            toX: toX, toY: toY
        )
    }
}
