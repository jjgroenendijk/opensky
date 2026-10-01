// A `RagdollSessionWorld` built from plain values, for `RagdollCoordinatorTests`.

@testable import OpenSkyCombat
@testable import OpenSkyFormatsAnimation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
import simd

final class FakeRagdollSessionWorld: RagdollSessionWorld {
    static let skeleton = HKASkeleton(
        name: "rig",
        bones: ["a", "b", "c"].map { HKABone(name: $0, lockTranslation: false) },
        parentIndices: [-1, 0, 1],
        referencePose: Array(
            repeating: HKABonePose(translation: .zero, rotation: .identityRotation, scale: .one),
            count: 3
        )
    )

    var ragdollResidents: [RagdollResident] = []
    var zeroHealth: Set<ReferenceKey> = []
    private(set) var murders: [ReferenceKey] = []
    var skeletonMeshPath = "meshes\\actors\\character\\character assets\\skeleton.nif"
    var scale: Float = 1
    var declaredPlayerEvents: Set<String> = []
    var selectedRagdollActor: ReferenceKey?
    var playerFeetPosition: SIMD3<Float>? = .zero
    var acceptsCorpseSearch = true
    private(set) var searchedCorpses: [ReferenceKey] = []
    var publishedRagdollPoses: [UInt32: [String: float4x4]] = [:]
    var ragdollStepWorld = DynamicStepWorld()

    func hasZeroHealth(_ key: ReferenceKey) -> Bool {
        zeroHealth.contains(key)
    }

    func reportMurder(of key: ReferenceKey) {
        murders.append(key)
    }

    /// Every resident has a pose; its reference is its object ID.
    func ragdollPose(of key: ReferenceKey) -> RagdollActorPose? {
        guard ragdollResidents.contains(where: { $0.key == key }) else { return nil }
        return RagdollActorPose(
            reference: Self.reference(of: key),
            cell: .interior(FormID(0x20)),
            scale: scale,
            actorToWorld: matrix_identity_float4x4,
            skeletonMeshPath: skeletonMeshPath,
            skeleton: Self.skeleton,
            animatedBoneMatrices: (0 ..< 3).map {
                MatrixMath.translation(SIMD3(Float($0) * 24, 0, 120))
            }
        )
    }

    func animatedPose(of key: ReferenceKey) -> [String: float4x4]? {
        ragdollResidents.contains { $0.key == key } ? [:] : nil
    }

    func raisePlayerGraphEvent(_ name: String) -> Bool {
        declaredPlayerEvents.contains(name)
    }

    func queueActorDeathEvents(for key: ReferenceKey, killer: ReferenceKey?) -> Int {
        2
    }

    func searchCorpse(_ key: ReferenceKey) -> Bool {
        searchedCorpses.append(key)
        return acceptsCorpseSearch
    }

    static func reference(of key: ReferenceKey) -> FormID {
        guard case let .plugin(_, objectID) = key else { return FormID(0) }
        return FormID(objectID)
    }
}
