// The value types NavmeshFixture packs into NVNM bytes. See NavmeshFixture.swift.

import Foundation
@testable import OpenSkyFormats

extension NavmeshFixture {
    /// One triangle as the fixture spells it, before packing.
    public struct Triangle: Sendable {
        public var vertices: SIMD3<UInt16>
        public var neighbors: SIMD3<Int16> = SIMD3(repeating: -1)
        public var flags: UInt16 = 0
        public var coverFlags: UInt16 = 0

        public init(
            vertices: SIMD3<UInt16>,
            neighbors: SIMD3<Int16> = SIMD3(repeating: -1),
            flags: UInt16 = 0,
            coverFlags: UInt16 = 0
        ) {
            self.vertices = vertices
            self.neighbors = neighbors
            self.flags = flags
            self.coverFlags = coverFlags
        }
    }

    public struct EdgeLink: Sendable {
        public var type: UInt32 = 0
        public var navmesh: UInt32
        public var triangle: Int16

        public init(type: UInt32 = 0, navmesh: UInt32, triangle: Int16) {
            self.type = type
            self.navmesh = navmesh
            self.triangle = triangle
        }
    }

    public struct DoorLink: Sendable {
        public var triangle: Int16
        public var door: UInt32

        public init(triangle: Int16, door: UInt32) {
            self.triangle = triangle
            self.door = door
        }
    }
}
