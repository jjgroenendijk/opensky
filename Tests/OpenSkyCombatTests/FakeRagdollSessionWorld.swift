// A `RagdollSessionWorld` built from plain values, for `RagdollCoordinatorTests`.

@testable import OpenSkyCombat
@testable import OpenSkyFormatsAnimation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
import simd

@MainActor
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

    static let cell = CellSceneLocation.interior(FormID(0x20))

    var ragdollResidents: [RagdollResident] = []
    var residentRagdollCells: Set<CellSceneLocation> = [FakeRagdollSessionWorld.cell]
    var zeroHealth: Set<ReferenceKey> = []
    var skeletonMeshPath = "meshes\\actors\\character\\character assets\\skeleton.nif"
    var scale: Float = 1
    var declaredPlayerEvents: Set<String> = []
    var selectedRagdollActor: ReferenceKey?
    var playerFeetPosition: SIMD3<Float>? = .zero
    var acceptsCorpseSearch = true
    private(set) var searchedCorpses: [ReferenceKey] = []
    var ragdollStepWorld = DynamicStepWorld()
    /// The nodes a death's weapon drop hides; empty drops nothing.
    var droppedWeaponNodes: [String] = []
    var severable: String?
    var keptCorpses: Set<ReferenceKey> = []
    private(set) var removedCorpses: [ReferenceKey] = []
    private(set) var dismemberments: [(ReferenceKey, String)] = []

    func hasZeroHealth(_ key: ReferenceKey) -> Bool {
        zeroHealth.contains(key)
    }

    /// Every resident has a pose; its reference is its object ID.
    func ragdollPose(of key: ReferenceKey) -> RagdollActorPose? {
        guard ragdollResidents.contains(where: { $0.key == key }) else { return nil }
        return RagdollActorPose(
            reference: Self.reference(of: key),
            cell: Self.cell,
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

    func dropWeapon(of _: ReferenceKey) -> [String] {
        droppedWeaponNodes
    }

    func severableNode(of _: ReferenceKey) -> String? {
        severable
    }

    func showDismemberment(of key: ReferenceKey, node: String, at _: SIMD3<Float>) {
        dismemberments.append((key, node))
    }

    func isCorpseKept(_ key: ReferenceKey) -> Bool {
        keptCorpses.contains(key)
    }

    func removeCorpse(_ key: ReferenceKey) {
        removedCorpses.append(key)
    }

    static func reference(of key: ReferenceKey) -> FormID {
        guard case let .plugin(_, objectID) = key else { return FormID(0) }
        return FormID(objectID)
    }
}
