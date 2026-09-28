// The rigid-body dynamics values NIFCollisionFixture.rigidBody writes.

import Foundation
@testable import OpenSkyFormats
import simd

extension NIFCollisionFixture {
    /// The inertial tail of `bhkRigidBodyCInfo2010`, so a test names only the
    /// fields it cares about. Values are in the file's own units: metres,
    /// kilograms, radians.
    public struct Dynamics: Sendable {
        public var linearVelocity: SIMD3<Float> = .zero
        public var angularVelocity: SIMD3<Float> = .zero
        /// Rows in nif.xml order: m11 m12 m13 | m21 m22 m23 | m31 m32 m33.
        public var inertiaRows: [SIMD3<Float>] = [
            SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)
        ]
        public var center: SIMD3<Float> = .zero
        public var mass: Float = 0
        public var linearDamping: Float = 0
        public var angularDamping: Float = 0
        public var timeFactor: Float = 1
        public var gravityFactor: Float = 1
        public var friction: Float = 0
        public var rollingFrictionMultiplier: Float = 0
        public var restitution: Float = 0
        public var maxLinearVelocity: Float = 0
        public var maxAngularVelocity: Float = 0
        public var penetrationDepth: Float = 0
        public var deactivatorType: UInt8 = 1
        public var solverDeactivation: UInt8 = 1
        public var qualityType: UInt8 = 1

        public init(
            linearVelocity: SIMD3<Float> = .zero,
            angularVelocity: SIMD3<Float> = .zero,
            inertiaRows: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)],
            center: SIMD3<Float> = .zero,
            mass: Float = 0,
            linearDamping: Float = 0,
            angularDamping: Float = 0,
            timeFactor: Float = 1,
            gravityFactor: Float = 1,
            friction: Float = 0,
            rollingFrictionMultiplier: Float = 0,
            restitution: Float = 0,
            maxLinearVelocity: Float = 0,
            maxAngularVelocity: Float = 0,
            penetrationDepth: Float = 0,
            deactivatorType: UInt8 = 1,
            solverDeactivation: UInt8 = 1,
            qualityType: UInt8 = 1
        ) {
            self.linearVelocity = linearVelocity
            self.angularVelocity = angularVelocity
            self.inertiaRows = inertiaRows
            self.center = center
            self.mass = mass
            self.linearDamping = linearDamping
            self.angularDamping = angularDamping
            self.timeFactor = timeFactor
            self.gravityFactor = gravityFactor
            self.friction = friction
            self.rollingFrictionMultiplier = rollingFrictionMultiplier
            self.restitution = restitution
            self.maxLinearVelocity = maxLinearVelocity
            self.maxAngularVelocity = maxAngularVelocity
            self.penetrationDepth = penetrationDepth
            self.deactivatorType = deactivatorType
            self.solverDeactivation = solverDeactivation
            self.qualityType = qualityType
        }
    }
}
