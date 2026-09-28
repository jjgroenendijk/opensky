// Skyrim SE LST tree-type atlas metadata + BTT placed-reference blocks.
// Layout source: xEdit dev-4.1.6 Core/wbLOD.pas,
// TwbLodTES5TreeType/TwbLodTES5TreeRef + LoadFromData implementations.

import Foundation
import simd

nonisolated enum TreeLODError: Error, Equatable {
    case invalidCount(Int32)
    case duplicateTypeIndex(Int32)
    case invalidType(index: Int32)
    case invalidReference(typeIndex: Int32, referenceIndex: Int)
    case trailingBytes(Int)
    case unknownTypeIndex(Int32)
}

nonisolated struct TreeLODType: Equatable {
    let index: Int32
    let width: Float
    let height: Float
    let uvMin: SIMD2<Float>
    let uvMax: SIMD2<Float>
    /// Opaque xEdit `Unknown` word. Retained for inventory, not interpreted.
    let metadata: UInt32
}

nonisolated struct TreeLODList: Equatable {
    static let recordSize = 32
    let types: [TreeLODType]

    init(data: Data) throws {
        var reader = BinaryReader(data)
        let count = try Int32(bitPattern: reader.readUInt32())
        guard count >= 0, Int64(count) <= Int64(reader.bytesRemaining / Self.recordSize) else {
            throw TreeLODError.invalidCount(count)
        }
        var parsed: [TreeLODType] = []
        var indices: Set<Int32> = []
        parsed.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let type = try TreeLODType(
                index: Int32(bitPattern: reader.readUInt32()),
                width: reader.readFloat32(),
                height: reader.readFloat32(),
                uvMin: SIMD2(reader.readFloat32(), reader.readFloat32()),
                uvMax: SIMD2(reader.readFloat32(), reader.readFloat32()),
                metadata: reader.readUInt32()
            )
            guard Self.isValid(type) else { throw TreeLODError.invalidType(index: type.index) }
            guard indices.insert(type.index).inserted else {
                throw TreeLODError.duplicateTypeIndex(type.index)
            }
            parsed.append(type)
        }
        guard reader.bytesRemaining == 0 else {
            throw TreeLODError.trailingBytes(reader.bytesRemaining)
        }
        types = parsed
    }

    func type(index: Int32) -> TreeLODType? {
        types.first { $0.index == index }
    }

    private static func isValid(_ type: TreeLODType) -> Bool {
        let values = [
            type.width, type.height,
            type.uvMin.x, type.uvMin.y,
            type.uvMax.x, type.uvMax.y
        ]
        return values.allSatisfy(\.isFinite)
            && type.width > 0 && type.height > 0
            && type.uvMin.x < type.uvMax.x && type.uvMin.y < type.uvMax.y
    }
}

nonisolated struct TreeLODReference: Equatable {
    let position: SIMD3<Float>
    /// Radians about +Z, generated in xEdit's 0...2pi range.
    let rotation: Float
    let scale: Float
    let formID: UInt32
    /// Opaque xEdit `Unknown1`/`Unknown2` words.
    let metadata1: UInt32
    let metadata2: UInt32
}

nonisolated struct TreeLODReferenceGroup: Equatable {
    let typeIndex: Int32
    let references: [TreeLODReference]
}

nonisolated struct TreeLODBlock: Equatable {
    static let referenceSize = 32
    let groups: [TreeLODReferenceGroup]

    init(data: Data, list: TreeLODList? = nil) throws {
        var reader = BinaryReader(data)
        let groupCount = try Int32(bitPattern: reader.readUInt32())
        guard groupCount >= 0, Int64(groupCount) <= Int64(reader.bytesRemaining / 8) else {
            throw TreeLODError.invalidCount(groupCount)
        }
        var parsed: [TreeLODReferenceGroup] = []
        parsed.reserveCapacity(Int(groupCount))
        for _ in 0 ..< groupCount {
            let typeIndex = try Int32(bitPattern: reader.readUInt32())
            if let list, list.type(index: typeIndex) == nil {
                throw TreeLODError.unknownTypeIndex(typeIndex)
            }
            let count = try Int32(bitPattern: reader.readUInt32())
            guard
                count >= 0,
                Int64(count) <= Int64(reader.bytesRemaining / Self.referenceSize)
            else {
                throw TreeLODError.invalidCount(count)
            }
            var references: [TreeLODReference] = []
            references.reserveCapacity(Int(count))
            for referenceIndex in 0 ..< Int(count) {
                let reference = try TreeLODReference(
                    position: SIMD3(
                        reader.readFloat32(), reader.readFloat32(), reader.readFloat32()
                    ),
                    rotation: reader.readFloat32(),
                    scale: reader.readFloat32(),
                    formID: reader.readUInt32(),
                    metadata1: reader.readUInt32(),
                    metadata2: reader.readUInt32()
                )
                guard Self.isValid(reference) else {
                    throw TreeLODError.invalidReference(
                        typeIndex: typeIndex,
                        referenceIndex: referenceIndex
                    )
                }
                references.append(reference)
            }
            parsed.append(TreeLODReferenceGroup(typeIndex: typeIndex, references: references))
        }
        guard reader.bytesRemaining == 0 else {
            throw TreeLODError.trailingBytes(reader.bytesRemaining)
        }
        groups = parsed
    }

    var referenceCount: Int {
        groups.reduce(0) { $0 + $1.references.count }
    }

    private static func isValid(_ reference: TreeLODReference) -> Bool {
        [
            reference.position.x, reference.position.y, reference.position.z,
            reference.rotation, reference.scale
        ].allSatisfy(\.isFinite) && reference.scale > 0
    }
}
