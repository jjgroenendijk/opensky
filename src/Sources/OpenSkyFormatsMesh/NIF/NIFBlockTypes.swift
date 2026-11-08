// The NIF block types engine code handles by name: it decodes them, or skips them on
// purpose. `openskycli gaps` lists the types the data holds and no code names.
// `make gap-registries` checks this list against the type names in the code.

import Foundation

nonisolated public enum NIFBlockTypes: Sendable {
    public static let handled: Set = [
        // Scene graph
        "NiNode", "BSFadeNode", "BSLeafAnimNode", "BSTreeNode", "BSOrderedNode",
        "BSMultiBoundNode", "NiSwitchNode",
        "NiBillboardNode", "NiCamera", "BSValueNode", "BSBlastNode", "BSDamageStage",
        "BSMultiBound", "BSMultiBoundAABB", "BSMultiBoundOBB",
        // Geometry and skinning
        "BSTriShape", "BSSubIndexTriShape", "BSDynamicTriShape", "NiSkinInstance",
        "BSDismemberSkinInstance", "NiSkinData", "NiSkinPartition", "NiTriShape",
        "BSLODTriShape", "NiTriShapeData",
        // Materials
        "BSLightingShaderProperty", "BSEffectShaderProperty", "BSWaterShaderProperty",
        "BSShaderTextureSet", "NiAlphaProperty", "BSSkyShaderProperty",
        // Extra data
        "NiStringExtraData", "NiTextKeyExtraData", "BSBehaviorGraphExtraData",
        "BSFurnitureMarker", "BSFurnitureMarkerNode", "BSXFlags", "BSInvMarker", "BSBound",
        "NiIntegerExtraData", "NiFloatExtraData", "NiBooleanExtraData", "NiStringsExtraData",
        "NiBinaryExtraData", "BSDistantObjectLargeRefExtraData",
        "BSDecalPlacementVectorExtraData", "BSBoneLODExtraData",
        // Animation controllers
        "NiControllerSequence", "NiTransformController", "NiMultiTargetTransformController",
        "NiKeyframeController", "NiVisController", "NiTransformInterpolator",
        "NiTransformData", "NiPoint3Interpolator", "NiPosData", "NiFloatInterpolator",
        "NiFloatData", "NiBoolInterpolator", "NiBoolTimelineInterpolator", "NiBoolData",
        "NiControllerManager", "NiDefaultAVObjectPalette", "NiBlendFloatInterpolator",
        "NiBlendBoolInterpolator", "NiBlendPoint3Interpolator", "NiPathInterpolator",
        "NiLookAtInterpolator", "BSEffectShaderPropertyFloatController",
        "BSEffectShaderPropertyColorController", "BSLightingShaderPropertyFloatController",
        "BSLightingShaderPropertyColorController", "BSNiAlphaPropertyTestRefController",
        "BSFrustumFOVController", "NiFloatExtraDataController", "BSLagBoneController",
        "BSProceduralLightningController", "NiBSBoneLODController",
        // Particles
        "NiParticleSystem", "BSStripParticleSystem", "NiPSysData", "BSStripPSysData",
        "NiPSysEmitterCtlr", "BSPSysMultiTargetEmitterCtlr", "NiPSysBoxEmitter",
        "NiPSysCylinderEmitter", "NiPSysSphereEmitter", "NiPSysMeshEmitter",
        "NiPSysAgeDeathModifier", "NiPSysSpawnModifier", "NiPSysRotationModifier",
        "NiPSysPositionModifier", "NiPSysBoundUpdateModifier", "NiPSysDragModifier",
        "NiPSysGravityModifier", "BSPSysInheritVelocityModifier", "BSPSysSubTexModifier",
        "BSPSysSimpleColorModifier", "BSPSysScaleModifier", "BSPSysLODModifier",
        "BSWindModifier", "BSMasterParticleSystem", "NiMeshParticleSystem", "NiMeshPSysData",
        "NiPSysUpdateCtlr", "NiPSysModifierActiveCtlr", "NiPSysEmitterSpeedCtlr",
        "NiPSysGravityStrengthCtlr", "NiPSysEmitterInitialRadiusCtlr", "NiPSysEmitterLifeSpanCtlr",
        "NiPSysEmitterDeclinationCtlr", "NiPSysEmitterPlanarAngleCtlr",
        "NiPSysInitialRotSpeedCtlr", "NiPSysBombModifier", "NiPSysColliderManager",
        "NiPSysPlanarCollider", "NiPSysSphericalCollider", "BSPSysRecycleBoundModifier",
        "BSPSysStripUpdateModifier", "NiPSysMeshUpdateModifier", "BSPSysHavokUpdateModifier",
        // Collision
        "bhkCollisionObject", "bhkBlendCollisionObject", "bhkRigidBody", "bhkRigidBodyT",
        "bhkMoppBvTreeShape", "bhkTransformShape", "bhkConvexTransformShape", "bhkListShape",
        "bhkCompressedMeshShape", "bhkCompressedMeshShapeData", "bhkPackedNiTriStripsShape",
        "bhkNiTriStripsShape", "NiTriStripsData", "hkPackedNiTriStripsData",
        "bhkConvexVerticesShape", "bhkBoxShape", "bhkSphereShape", "bhkCapsuleShape",
        "bhkCylinderShape", "bhkPlaneShape", "bhkSPCollisionObject", "bhkSimpleShapePhantom",
        // Constraints
        "bhkBallAndSocketConstraint", "bhkHingeConstraint", "bhkLimitedHingeConstraint",
        "bhkPrismaticConstraint", "bhkRagdollConstraint", "bhkStiffSpringConstraint",
        "bhkMalleableConstraint", "bhkBreakableConstraint", "bhkBallSocketConstraintChain"
    ]
}
