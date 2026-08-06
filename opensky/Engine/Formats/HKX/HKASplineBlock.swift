// Spline block grammar + sampling for hkaSplineCompressedAnimation. See
// HKASplineCompressedAnimation.swift + docs/formats/hka-animation.md for
// clean-room sources, probe evidence, scope, and unsupported variants.

import Foundation
import simd

nonisolated struct HKASplineBlockLayout {
    let blockIndex: Int
    let start: Int
    let end: Int
    let transformByteCount: Int
    let transformTrackCount: Int
    let floatTrackCount: Int
}

nonisolated struct HKASplineBlock {
    private let tracks: [HKASplineTransformTrack]

    static func decode(
        data: Data,
        layout: HKASplineBlockLayout
    ) throws -> HKASplineBlock {
        guard layout.start >= 0, layout.end >= layout.start, layout.end <= data.count else {
            throw HKASplineAnimationError.blockOutOfBounds(
                blockIndex: layout.blockIndex, offset: layout.start, limit: data.count
            )
        }
        let transformEnd = layout.start + layout.transformByteCount
        guard transformEnd >= layout.start, transformEnd <= layout.end else {
            throw HKASplineAnimationError.blockOutOfBounds(
                blockIndex: layout.blockIndex, offset: transformEnd, limit: layout.end
            )
        }
        var maskCursor = HKASplineCursor(
            data: data,
            blockIndex: layout.blockIndex,
            offset: layout.start,
            limit: transformEnd
        )
        let masks = try readMasks(cursor: &maskCursor, layout: layout)
        let tracks = try decodeTracks(cursor: &maskCursor, masks: masks)
        let consumed = maskCursor.offset - layout.start
        guard maskCursor.offset == transformEnd else {
            throw HKASplineAnimationError.blockSizeMismatch(
                blockIndex: layout.blockIndex,
                expected: layout.transformByteCount,
                consumed: consumed
            )
        }
        return HKASplineBlock(tracks: tracks)
    }

    private static func readMasks(
        cursor: inout HKASplineCursor,
        layout: HKASplineBlockLayout
    ) throws -> [HKASplineTransformMask] {
        var masks: [HKASplineTransformMask] = []
        masks.reserveCapacity(layout.transformTrackCount)
        for _ in 0 ..< layout.transformTrackCount {
            try masks.append(HKASplineTransformMask(
                quantization: cursor.readUInt8(),
                position: cursor.readUInt8(),
                rotation: cursor.readUInt8(),
                scale: cursor.readUInt8()
            ))
        }
        try cursor.skip(layout.floatTrackCount)
        try cursor.align(to: 4)
        return masks
    }

    private static func decodeTracks(
        cursor: inout HKASplineCursor,
        masks: [HKASplineTransformMask]
    ) throws -> [HKASplineTransformTrack] {
        var tracks: [HKASplineTransformTrack] = []
        tracks.reserveCapacity(masks.count)
        for (trackIndex, mask) in masks.enumerated() {
            let translationDescriptor = HKASplineVectorDescriptor(
                typeMask: mask.position,
                quantization: Int(mask.quantization & 0x03),
                identity: 0,
                trackIndex: trackIndex,
                component: "translation"
            )
            let translation = try HKASplineTrackDecoder.decodeVector(
                cursor: &cursor, descriptor: translationDescriptor
            )
            let rotation = try HKASplineTrackDecoder.decodeRotation(
                cursor: &cursor,
                typeMask: mask.rotation,
                quantization: Int((mask.quantization >> 2) & 0x0F) + 2,
                trackIndex: trackIndex
            )
            try cursor.align(to: 4)
            let scaleDescriptor = HKASplineVectorDescriptor(
                typeMask: mask.scale,
                quantization: Int((mask.quantization >> 6) & 0x03),
                identity: 1,
                trackIndex: trackIndex,
                component: "scale"
            )
            let scale = try HKASplineTrackDecoder.decodeVector(
                cursor: &cursor, descriptor: scaleDescriptor
            )
            tracks.append(HKASplineTransformTrack(
                translation: translation,
                rotation: rotation,
                scale: scale
            ))
        }
        return tracks
    }

    func localTransforms(at localFrame: Float) throws -> [HKABonePose] {
        var result: [HKABonePose] = []
        result.reserveCapacity(tracks.count)
        for (index, track) in tracks.enumerated() {
            let translation = track.translation.value(at: localFrame)
            let rotationVector = track.rotation.value(at: localFrame)
            let scale = track.scale.value(at: localFrame)
            let lanes = [
                translation.x, translation.y, translation.z,
                rotationVector.x, rotationVector.y, rotationVector.z, rotationVector.w,
                scale.x, scale.y, scale.z
            ]
            let maxMagnitude: Float = 1_000_000
            guard lanes.allSatisfy({ $0.isFinite && abs($0) <= maxMagnitude }) else {
                throw HKASplineAnimationError.nonFiniteTransform(trackIndex: index)
            }
            let norm = simd_length(rotationVector)
            guard norm.isFinite, norm > 0.000_001 else {
                throw HKASplineAnimationError.nonFiniteTransform(trackIndex: index)
            }
            result.append(HKABonePose(
                translation: translation,
                rotation: simd_quatf(vector: rotationVector / norm),
                scale: scale
            ))
        }
        return result
    }
}

nonisolated private enum HKASplineTrackDecoder {
    // MARK: - Transform tracks

    static func decodeVector(
        cursor: inout HKASplineCursor,
        descriptor: HKASplineVectorDescriptor
    ) throws -> HKASplineVectorTrack {
        let types = subTrackTypes(typeMask: descriptor.typeMask)
        guard types.contains(.spline) else {
            return try decodeConstantVector(
                cursor: &cursor, descriptor: descriptor, types: types
            )
        }
        guard descriptor.quantization == 0 || descriptor.quantization == 1 else {
            throw HKASplineAnimationError.unsupportedQuantization(
                trackIndex: descriptor.trackIndex,
                component: descriptor.component,
                code: descriptor.quantization
            )
        }
        let header = try cursor.readSplineHeader(
            trackIndex: descriptor.trackIndex, component: descriptor.component
        )
        try cursor.align(to: 4)
        let components = try readVectorComponents(
            cursor: &cursor, descriptor: descriptor, types: types
        )
        let controlPoints = try readVectorControlPoints(
            cursor: &cursor,
            descriptor: descriptor,
            types: types,
            bounds: components.bounds,
            count: header.controlPointCount
        )
        try cursor.align(to: 4)
        return HKASplineVectorTrack(
            constants: SIMD3(
                components.constants[0],
                components.constants[1],
                components.constants[2]
            ),
            types: types,
            header: header,
            controlPoints: controlPoints
        )
    }

    private static func subTrackTypes(typeMask: UInt8) -> [HKASplineSubTrackType] {
        (0 ..< 3).map { axis in
            if typeMask & (1 << axis) != 0 {
                return .constant
            }
            if typeMask & (1 << (axis + 4)) != 0 {
                return .spline
            }
            return .identity
        }
    }

    private static func decodeConstantVector(
        cursor: inout HKASplineCursor,
        descriptor: HKASplineVectorDescriptor,
        types: [HKASplineSubTrackType]
    ) throws -> HKASplineVectorTrack {
        var components = [Float](repeating: descriptor.identity, count: 3)
        for axis in 0 ..< 3 where types[axis] == .constant {
            components[axis] = try cursor.readFiniteFloat(
                trackIndex: descriptor.trackIndex, component: descriptor.component
            )
        }
        return HKASplineVectorTrack(constants: SIMD3(
            components[0], components[1], components[2]
        ))
    }

    private static func readVectorComponents(
        cursor: inout HKASplineCursor,
        descriptor: HKASplineVectorDescriptor,
        types: [HKASplineSubTrackType]
    ) throws -> (bounds: [HKASplineBounds?], constants: [Float]) {
        var bounds = [HKASplineBounds?](repeating: nil, count: 3)
        var constants = [Float](repeating: descriptor.identity, count: 3)
        for axis in 0 ..< 3 {
            switch types[axis] {
            case .spline:
                let minimum = try cursor.readFiniteFloat(
                    trackIndex: descriptor.trackIndex, component: descriptor.component
                )
                let maximum = try cursor.readFiniteFloat(
                    trackIndex: descriptor.trackIndex, component: descriptor.component
                )
                guard maximum >= minimum else {
                    throw HKASplineAnimationError.invalidSpline(
                        trackIndex: descriptor.trackIndex,
                        component: descriptor.component,
                        reason: "maximum below minimum"
                    )
                }
                bounds[axis] = HKASplineBounds(minimum: minimum, maximum: maximum)
            case .constant:
                constants[axis] = try cursor.readFiniteFloat(
                    trackIndex: descriptor.trackIndex, component: descriptor.component
                )
            case .identity:
                break
            }
        }
        return (bounds, constants)
    }

    private static func readVectorControlPoints(
        cursor: inout HKASplineCursor,
        descriptor: HKASplineVectorDescriptor,
        types: [HKASplineSubTrackType],
        bounds: [HKASplineBounds?],
        count: Int
    ) throws -> [[Float]] {
        var controlPoints = [[Float]](repeating: [], count: 3)
        for axis in 0 ..< 3 where types[axis] == .spline {
            controlPoints[axis].reserveCapacity(count)
        }
        for _ in 0 ..< count {
            for axis in 0 ..< 3 where types[axis] == .spline {
                let normalized: Float = if descriptor.quantization == 0 {
                    try Float(cursor.readUInt8()) / 255
                } else {
                    try Float(cursor.readUInt16()) / 65535
                }
                guard let axisBounds = bounds[axis] else {
                    throw HKASplineAnimationError.invalidSpline(
                        trackIndex: descriptor.trackIndex,
                        component: descriptor.component,
                        reason: "missing dynamic-axis bounds"
                    )
                }
                controlPoints[axis].append(
                    axisBounds.minimum + (axisBounds.maximum - axisBounds.minimum) * normalized
                )
            }
        }
        return controlPoints
    }

    static func decodeRotation(
        cursor: inout HKASplineCursor,
        typeMask: UInt8,
        quantization: Int,
        trackIndex: Int
    ) throws -> HKASplineQuaternionTrack {
        let isSpline = typeMask & 0xF0 != 0
        let isConstant = typeMask & 0x0F != 0
        guard isSpline || isConstant else { return .identity }
        guard quantization == 3 else {
            throw HKASplineAnimationError.unsupportedQuantization(
                trackIndex: trackIndex,
                component: "rotation",
                code: quantization
            )
        }
        guard isSpline else {
            return try .constant(cursor.readQuaternion40())
        }
        let header = try cursor.readSplineHeader(
            trackIndex: trackIndex, component: "rotation"
        )
        var controlPoints: [SIMD4<Float>] = []
        controlPoints.reserveCapacity(header.controlPointCount)
        for _ in 0 ..< header.controlPointCount {
            try controlPoints.append(cursor.readQuaternion40())
        }
        return .spline(header: header, controlPoints: controlPoints)
    }
}
