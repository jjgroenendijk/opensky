// The converted payloads decode to exactly what the direct load path builds:
// flattened models, collision models, and shipped texture levels.

import Foundation
@testable import OpenSkyAssetCache
import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import simd
import Testing

struct AssetPayloadCodecTests {
    private func bytes(_ values: [some Any]) -> Data {
        values.withUnsafeBytes { Data($0) }
    }

    private var skinnedModel: Model {
        let skinning = MeshSkinning(
            weights: [SIMD4(0.5, 0.5, 0, 0), SIMD4(1, 0, 0, 0), SIMD4(0.25, 0.75, 0, 0)],
            boneIndices: [SIMD4(0, 1, 0, 0), SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0)],
            bindPoseMatrices: [matrix_identity_float4x4, MatrixMath.translation(SIMD3(1, 2, 3))],
            boneNames: ["NPC Root [Root]", "NPC Spine"],
            rootParentToSkin: MatrixMath.translation(SIMD3(0, 0, 9)),
            skinToBoneMatrices: [matrix_identity_float4x4]
        )
        let mesh = Mesh(
            name: "Body", transform: MatrixMath.translation(SIMD3(4, 5, 6)),
            positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0.1)],
            normals: [SIMD3(0, 0, 1), SIMD3(0, 0, 1), SIMD3(0, 0, 1)],
            tangents: [], bitangents: [],
            uvs: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1)],
            colors: [SIMD4(1, 0.5, 0.25, 1), SIMD4(1, 1, 1, 1), SIMD4(0, 0, 0, 1)],
            indices: [0, 1, 2], materialSlot: 1, skinning: skinning
        )
        let plain = Mesh(
            name: nil, transform: matrix_identity_float4x4, positions: [SIMD3(9, 9, 9)],
            normals: [], tangents: [SIMD3(1, 0, 0)], bitangents: [SIMD3(0, 1, 0)], uvs: [],
            colors: [], indices: [0, 0, 0], materialSlot: 0
        )
        let cutout = Material(
            diffuseTexture: "textures\\a.dds", normalTexture: nil, uvOffset: SIMD2(0.5, 0),
            uvScale: SIMD2(2, 2), alpha: 0.75, glossiness: 30, specularColor: SIMD3(1, 0.5, 0),
            specularStrength: 2, doubleSided: true, alphaBlend: false, alphaTestThreshold: 0.5
        )
        let foam = Material(
            diffuseTexture: "textures/effects/foam.dds", normalTexture: nil, uvOffset: .zero,
            uvScale: SIMD2(1, 1), alpha: 1, glossiness: 80, specularColor: SIMD3(1, 1, 1),
            specularStrength: 0, doubleSided: true, alphaBlend: true, alphaTestThreshold: nil,
            effect: EffectShading(
                baseColor: SIMD4(1, 0.5, 0.25, 0.75), baseColorScale: 2,
                paletteTexture: "textures/effects/gradients/foam.dds", paletteColor: true,
                paletteAlpha: false, falloff: SIMD4(0.9, 0.1, 1, 0), vertexColors: true,
                vertexAlpha: false
            )
        )
        return Model(
            meshes: [mesh, plain],
            materials: [.fallback, cutout, foam, .waterSurface],
            skippedShapeCount: 2,
            editorMarkerShapeCount: 1
        )
    }

    @Test func aModelDecodesToTheSameArraysAndMaterials() throws {
        let model = skinnedModel
        let decoded = try ModelCacheCodec.decode(ModelCacheCodec.encode(model))
        #expect(decoded.materials == model.materials)
        #expect(decoded.skippedShapeCount == 2)
        #expect(decoded.editorMarkerShapeCount == 1)
        #expect(decoded.meshes.count == model.meshes.count)
        for (left, right) in zip(decoded.meshes, model.meshes) {
            #expect(left.name == right.name)
            #expect(left.transform == right.transform)
            #expect(bytes(left.positions) == bytes(right.positions))
            #expect(bytes(left.normals) == bytes(right.normals))
            #expect(bytes(left.tangents) == bytes(right.tangents))
            #expect(bytes(left.bitangents) == bytes(right.bitangents))
            #expect(left.uvs == right.uvs)
            #expect(left.colors == right.colors)
            #expect(left.indices == right.indices)
            #expect(left.materialSlot == right.materialSlot)
            #expect(left.skinning?.weights == right.skinning?.weights)
            #expect(left.skinning?.boneIndices == right.skinning?.boneIndices)
            #expect(left.skinning?.bindPoseMatrices == right.skinning?.bindPoseMatrices)
            #expect(left.skinning?.boneNames == right.skinning?.boneNames)
            #expect(left.skinning?.rootParentToSkin == right.skinning?.rootParentToSkin)
            #expect(left.skinning?.skinToBoneMatrices == right.skinning?.skinToBoneMatrices)
        }
    }

    @Test func aTruncatedModelPayloadThrows() {
        let data = ModelCacheCodec.encode(skinnedModel)
        #expect(throws: CachePayloadError.self) {
            try ModelCacheCodec.decode(data.prefix(data.count - 3))
        }
    }

    private var dynamics: NIFRigidBodyDynamics {
        NIFRigidBodyDynamics(
            mass: 3, inertiaTensor: matrix_identity_float3x3, centerOfMass: SIMD3(1, 2, 3),
            linearVelocity: .zero, angularVelocity: .zero, linearDamping: 0.1, angularDamping: 0.05,
            timeFactor: 1, gravityFactor: 1, friction: 0.5, rollingFrictionMultiplier: 0,
            restitution: 0.3, maxLinearVelocity: 100, maxAngularVelocity: 30,
            penetrationDepth: 0.15,
            rawMotionSystem: 7, rawDeactivatorType: 1, rawSolverDeactivation: 2, rawQualityType: 3
        )
    }

    private var collisionModel: NIFCollisionModel {
        let filter = NIFCollisionFilter(layer: 1, flags: 0x40, group: 9)
        let shapes: [NIFCollisionShape] = [
            NIFCollisionShape(
                transform: MatrixMath.translation(SIMD3(0, 0, 1)),
                geometry: .triangleSoup(
                    vertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
                    indices: [0, 1, 2]
                ),
                material: 0xDEAD_BEEF
            ),
            NIFCollisionShape(transform: matrix_identity_float4x4, geometry: .convexVertices(
                vertices: [SIMD3(0, 0, 0), SIMD3(1, 1, 1)], hullIndices: [0, 1, 0]
            )),
            NIFCollisionShape(
                transform: matrix_identity_float4x4,
                geometry: .box(halfExtents: SIMD3(1, 2, 3))
            ),
            NIFCollisionShape(transform: matrix_identity_float4x4, geometry: .sphere(radius: 4)),
            NIFCollisionShape(transform: matrix_identity_float4x4, geometry: .capsule(
                first: SIMD3(0, 0, 0), second: SIMD3(0, 0, 5), radius: 1
            ))
        ]
        let body = NIFCollisionBody(
            targetBlock: 3, targetName: "Rock", bodyBlock: 4, carrier: .collisionObject,
            collisionObjectFlags: 0x81, worldFilter: filter, rigidBodyFilter: filter,
            entityResponse: 1,
            rigidBodyResponse: 1, dynamics: dynamics, constraints: [], bodyFlags: 2,
            transform: MatrixMath.translation(SIMD3(7, 8, 9)), shapes: shapes
        )
        return NIFCollisionModel(
            bodies: [body], unsupportedReachableBlocks: ["bhkMultiSphereShape": 2],
            decodeFailures: [NIFCollisionFailure(block: 11, message: "bad ref")]
        )
    }

    @Test func aCollisionModelDecodesToTheSameBodiesAndShapes() throws {
        let model = collisionModel
        let payload = try #require(CollisionCacheCodec.encode(model))
        let decoded = try CollisionCacheCodec.decode(payload)
        #expect(decoded.unsupportedReachableBlocks == model.unsupportedReachableBlocks)
        #expect(decoded.decodeFailures == model.decodeFailures)
        #expect(decoded.shapeCount == model.shapeCount)
        #expect(decoded.triangleCount == model.triangleCount)
        #expect(decoded.bounds == model.bounds)
        let left = try #require(decoded.bodies.first)
        let right = try #require(model.bodies.first)
        #expect(left.targetName == right.targetName)
        #expect(left.worldFilter == right.worldFilter)
        #expect(left.bodyFlags == right.bodyFlags)
        #expect(left.transform == right.transform)
        #expect(bytes([left.dynamics]) == bytes([right.dynamics]))
        #expect(left.shapes.map(\.material) == right.shapes.map(\.material))
        #expect(String(describing: left.shapes.map(\.geometry)) ==
            String(describing: right.shapes.map(\.geometry)))
    }

    @Test func aCollisionModelWithJointsIsNotCached() throws {
        let model = collisionModel
        let body = try #require(model.bodies.first)
        let joint = NIFCollisionConstraint(
            block: 1,
            entityA: 4,
            entityB: 4,
            priority: 1,
            data: .ballAndSocket(NIFBallAndSocketConstraint(pivotA: .zero, pivotB: .zero))
        )
        let jointed = NIFCollisionBody(
            targetBlock: body.targetBlock, targetName: body.targetName, bodyBlock: body.bodyBlock,
            carrier: body.carrier, collisionObjectFlags: 0, worldFilter: body.worldFilter,
            rigidBodyFilter: body.rigidBodyFilter, entityResponse: 1, rigidBodyResponse: 1,
            dynamics: body.dynamics, constraints: [joint], bodyFlags: 0, transform: body.transform,
            shapes: body.shapes
        )
        let withJoint = NIFCollisionModel(
            bodies: [jointed],
            unsupportedReachableBlocks: [:],
            decodeFailures: []
        )
        #expect(CollisionCacheCodec.encode(withJoint) == nil)
    }

    @Test(arguments: [DDSPixelFormat.bc1, .bc3, .bc5, .bc7])
    func shippedTextureLevelsAreStoredAsTheyAre(format: DDSPixelFormat) throws {
        let dds = try DDSFile(data: DDSFixture.file(
            format: format,
            width: 16,
            height: 8,
            mipCount: 5
        ))
        let ready = try ReadyTextureCodec.decode(ReadyTextureCodec.encode(ReadyTexture(dds: dds)))
        #expect(ready.format == ReadyTextureFormat(format))
        #expect(ready.mipCount == dds.mipCount)
        for level in 0 ..< dds.mipCount {
            let range = ready.levelRange(level)
            let start = ready.bytes.startIndex
            #expect(Data(ready.bytes[(start + range.lowerBound) ..< (start + range.upperBound)]) ==
                dds.mipData(level: level))
            #expect(ready.bytesPerRow(level: level) == dds.bytesPerRow(level: level))
        }
    }

    @Test func xrgbTexturesGetTheOpaqueAlphaTheDirectUploadGives() throws {
        let dds = try DDSFile(data: DDSFixture.xrgb8888File(width: 4, height: 4, mipCount: 1))
        let ready = ReadyTexture(dds: dds)
        #expect(ready.format == .bgra8)
        #expect(stride(from: 3, to: ready.bytes.count, by: 4).allSatisfy { ready.bytes[$0] == 255 })
    }

    @Test func aDDSLayoutTheEngineDoesNotReadIsNotStored() throws {
        let rgb16 = DDSFixture.xrgb8888File(width: 4, height: 4, mipCount: 1, bitCount: 16)
        #expect(try ShippedTextureConverter().convert(
            path: "textures\\a.dds", bytes: rgb16, output: AssetTextureOutput()
        ) == nil)
    }

    @Test func aTexturePayloadWithMissingBytesThrows() throws {
        let dds = try DDSFile(data: DDSFixture.file(format: .bc1, width: 8, height: 8, mipCount: 4))
        let payload = ReadyTextureCodec.encode(ReadyTexture(dds: dds))
        #expect(throws: ReadyTextureError.self) {
            try ReadyTextureCodec.decode(payload.prefix(payload.count - 1))
        }
    }
}
