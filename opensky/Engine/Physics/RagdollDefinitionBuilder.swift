// Building a `RagdollDefinition` from decoded skeleton data (issue #197,
// roadmap item 15.6), split from the value types for the file-length limit.
//
// The input is exactly what item 15.1 already produces plus what the animation
// layer already holds: an `NIFCollisionModel` decoded from `skeleton.nif`, and
// the animation skeleton's bone names with the bind-pose world matrix of each.
// Nothing here reads a file.
//
// Documented in docs/engine/ragdoll.md.

import simd

nonisolated extension RagdollDefinition {
    /// Resolves a decoded skeleton NIF onto an animation skeleton.
    ///
    /// `bindMatrices` are the bone world matrices of the skeleton's own
    /// reference pose, in the same model space `NIFCollisionBody.transform`
    /// places bodies in. `SkeletonPoseMath.worldMatrices(skeleton:localPoses:)`
    /// over the reference pose produces exactly that list.
    ///
    /// Nil only when nothing at all survived: no body resolved onto a bone. A
    /// partial ragdoll is a result, not a failure, and `skipped` says what was
    /// lost.
    init?(
        model: NIFCollisionModel,
        boneNames: [String],
        bindMatrices: [float4x4],
        scale: Float = 1
    ) {
        guard scale > 0, scale.isFinite else { return nil }
        let resolved = Self.resolveBodies(
            model: model, boneNames: boneNames, bindMatrices: bindMatrices, scale: scale
        )
        guard !resolved.bones.isEmpty else { return nil }
        let joints = Self.resolveJoints(model: model, bodies: resolved)
        self.init(
            bones: resolved.bones,
            joints: joints.joints,
            skipped: resolved.skipped + joints.skipped
        )
    }

    /// Everything the body pass produced: the bones themselves, the placement
    /// each was built under so the joint pass can re-express a pivot, the block
    /// index each answers to, and what was dropped.
    private struct ResolvedBodies {
        var bones: [RagdollBoneDefinition] = []
        var placements: [Int: RagdollBodyPlacement] = [:]
        var indexByBlock: [Int: Int] = [:]
        var skipped: [RagdollBuildSkip] = []
    }

    /// One simulable body per named bone the animation skeleton has.
    private static func resolveBodies(
        model: NIFCollisionModel,
        boneNames: [String],
        bindMatrices: [float4x4],
        scale: Float
    ) -> ResolvedBodies {
        var indexByName: [String: Int] = [:]
        for (index, name) in boneNames.enumerated() where indexByName[name] == nil {
            indexByName[name] = index
        }
        let scaling = MatrixMath.scale(uniform: scale)
        var resolved = ResolvedBodies()
        for body in model.bodies where body.dynamics.isSimulated {
            guard let name = body.targetName, !name.isEmpty else {
                resolved.skipped.append(.unnamedBody(block: body.bodyBlock))
                continue
            }
            guard let boneIndex = indexByName[name], boneIndex < bindMatrices.count else {
                resolved.skipped.append(.unresolvedBoneName(name))
                continue
            }
            guard
                let definition = DynamicBodyDefinition(bodies: [body], referenceScale: scale)
            else {
                resolved.skipped.append(.unsimulableBody(name))
                continue
            }
            resolved.indexByBlock[body.bodyBlock] = resolved.bones.count
            resolved.placements[body.bodyBlock] = RagdollBodyPlacement(
                matrix: scaling * body.transform,
                center: definition.centerOfMass
            )
            resolved.bones.append(RagdollBoneDefinition(
                boneName: name,
                boneIndex: boneIndex,
                body: definition,
                bindBoneMatrix: bindMatrices[boneIndex]
            ))
        }
        return resolved
    }

    /// One joint per decoded constraint whose two ends both resolved.
    private static func resolveJoints(
        model: NIFCollisionModel,
        bodies: ResolvedBodies
    ) -> (joints: [RagdollJointDefinition], skipped: [RagdollBuildSkip]) {
        var joints: [RagdollJointDefinition] = []
        var skipped: [RagdollBuildSkip] = []
        for constraint in model.constraints {
            guard
                let first = bodies.indexByBlock[Int(constraint.entityA)],
                let second = bodies.indexByBlock[Int(constraint.entityB)],
                first != second,
                let placementA = bodies.placements[Int(constraint.entityA)],
                let placementB = bodies.placements[Int(constraint.entityB)]
            else {
                skipped.append(.unresolvedJointEnd(block: constraint.block))
                continue
            }
            guard
                let joint = RagdollJointDefinition(
                    data: constraint.data.unwrapped,
                    bodyA: first,
                    bodyB: second,
                    placementA: placementA,
                    placementB: placementB
                )
            else {
                skipped.append(.unlimitedJointClass(constraint.type.className))
                continue
            }
            joints.append(joint)
        }
        return (joints: joints, skipped: skipped)
    }
}

/// Where one decoded body ended up, which is all the joint pass needs to carry
/// an entity-space pivot into the body's own centre-of-mass-local frame.
nonisolated struct RagdollBodyPlacement: Sendable {
    /// Entity space to model space, at the actor's scale.
    let matrix: float4x4
    /// The body's centre of mass in model space.
    let center: SIMD3<Float>

    /// A pivot authored in entity space, in the body's own frame.
    func localPivot(_ pivot: SIMD3<Float>) -> SIMD3<Float> {
        DynamicCollisionMath.transform(pivot, by: matrix) - center
    }

    /// An axis authored in entity space, in the body's own frame. Rotation
    /// only: a direction picks up no translation, and the uniform scale a
    /// placement may carry is divided back out by normalizing.
    func localAxis(_ axis: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let rotated = matrix.upperLeft * axis
        let length = simd_length(rotated)
        guard length > Float.ulpOfOne, rotated.isFiniteVector else { return fallback }
        return rotated / length
    }
}

nonisolated extension RagdollJointDefinition {
    /// One decoded joint in solver terms, or nil for a class this solver has no
    /// limits for.
    ///
    /// The two frames a hinge and a ragdoll cone carry are read into the same
    /// two-axis shape: `primaryAxis` is the thing the joint is *about* — the
    /// cone's twist axis, the hinge's rotation axis — and `secondaryAxis` is the
    /// reference direction a rotation about the primary one is measured from.
    init?(
        data: NIFConstraintData,
        bodyA: Int,
        bodyB: Int,
        placementA: RagdollBodyPlacement,
        placementB: RagdollBodyPlacement
    ) {
        switch data {
        case let .ragdoll(joint):
            self.init(
                bodyA: bodyA,
                bodyB: bodyB,
                frameA: placementA.frame(joint.frameA),
                frameB: placementB.frame(joint.frameB),
                limits: .cone(
                    coneMaxAngle: joint.coneMaxAngle,
                    planeMinAngle: joint.planeMinAngle,
                    planeMaxAngle: joint.planeMaxAngle,
                    twistMinAngle: joint.twistMinAngle,
                    twistMaxAngle: joint.twistMaxAngle
                ),
                maxFriction: joint.maxFriction
            )
        case let .hinge(joint):
            self.init(
                bodyA: bodyA,
                bodyB: bodyB,
                frameA: placementA.frame(joint.frameA),
                frameB: placementB.frame(joint.frameB),
                limits: .hinge
            )
        case let .limitedHinge(joint):
            self.init(
                bodyA: bodyA,
                bodyB: bodyB,
                frameA: placementA.frame(joint.frameA),
                frameB: placementB.frame(joint.frameB),
                limits: .limitedHinge(minAngle: joint.minAngle, maxAngle: joint.maxAngle),
                maxFriction: joint.maxFriction
            )
        case let .ballAndSocket(joint):
            self.init(
                bodyA: bodyA,
                bodyB: bodyB,
                frameA: placementA.pointFrame(joint.pivotA),
                frameB: placementB.pointFrame(joint.pivotB),
                limits: .point
            )
        case let .stiffSpring(joint):
            self.init(
                bodyA: bodyA,
                bodyB: bodyB,
                frameA: placementA.pointFrame(joint.pivotA),
                frameB: placementB.pointFrame(joint.pivotB),
                limits: .distance(length: joint.length)
            )
        case .prismatic, .malleable:
            // A rail joint and an already-unwrapped malleable wrapper both mean
            // the decode reached something this solver has no limit model for.
            // Dropping the joint is the honest outcome: holding its pivots
            // together while leaving five degrees of freedom open would look
            // like a solved joint and behave like a hinge nobody authored.
            return nil
        }
    }
}

nonisolated extension RagdollBodyPlacement {
    /// A hinge-family end in solver terms.
    func frame(_ hinge: NIFConstraintHingeFrame) -> RagdollJointFrame {
        RagdollJointFrame(
            pivot: localPivot(hinge.pivot),
            primaryAxis: localAxis(hinge.axis, fallback: SIMD3(1, 0, 0)),
            secondaryAxis: localAxis(hinge.perpAxis1, fallback: SIMD3(0, 1, 0))
        )
    }

    /// A ragdoll-cone end in solver terms.
    func frame(_ ragdoll: NIFConstraintRagdollFrame) -> RagdollJointFrame {
        RagdollJointFrame(
            pivot: localPivot(ragdoll.pivot),
            primaryAxis: localAxis(ragdoll.twist, fallback: SIMD3(1, 0, 0)),
            secondaryAxis: localAxis(ragdoll.plane, fallback: SIMD3(0, 1, 0))
        )
    }

    /// An end that carries a pivot and no axes, whose axes stay at the identity
    /// basis because nothing reads them.
    func pointFrame(_ pivot: SIMD3<Float>) -> RagdollJointFrame {
        RagdollJointFrame(
            pivot: localPivot(pivot),
            primaryAxis: RagdollJointFrame.identity.primaryAxis,
            secondaryAxis: RagdollJointFrame.identity.secondaryAxis
        )
    }
}

nonisolated extension NIFConstraintType {
    /// The `bhk` class name, for the skip tally the acceptance gate reads.
    var className: String {
        switch self {
        case .ballAndSocket: "bhkBallAndSocketConstraint"
        case .hinge: "bhkHingeConstraint"
        case .limitedHinge: "bhkLimitedHingeConstraint"
        case .prismatic: "bhkPrismaticConstraint"
        case .ragdoll: "bhkRagdollConstraint"
        case .stiffSpring: "bhkStiffSpringConstraint"
        case .malleable: "bhkMalleableConstraint"
        }
    }
}

nonisolated extension float4x4 {
    /// The rotation-and-scale block, for carrying a direction through a
    /// placement without picking up its translation.
    var upperLeft: float3x3 {
        float3x3(columns.0.xyz, columns.1.xyz, columns.2.xyz)
    }
}
